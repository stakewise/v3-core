// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IController} from '../interfaces/IController.sol';
import {IVaultEnterExit} from '../interfaces/IVaultEnterExit.sol';
import {IVaultToken} from '../interfaces/IVaultToken.sol';
import {IVaultsRegistry} from '../interfaces/IVaultsRegistry.sol';
import {IOsToken} from '../interfaces/IOsToken.sol';
import {IKeeperRewards} from '../interfaces/IKeeperRewards.sol';

/**
 * @title Controller
 * @author StakeWise
 * @notice Defines the functionality for minting and burning the osToken
 */
contract Controller is IController {
  using EnumerableSet for EnumerableSet.AddressSet;

  uint256 private constant _wad = 1e18;
  uint256 internal constant _maxPercent = 10_000; // @dev 100.00 %

  IOsToken private immutable _osToken;
  IKeeperRewards private immutable _keeper;
  IVaultsRegistry private immutable _vaultsRegistry;

  /// @inheritdoc IController
  uint256 public constant override healthFactorLiqThreshold = 1e18;
  uint256 public constant override maxVaultsCount = 10;

  /// @inheritdoc IController
  uint256 public override liqThresholdPercent;

  /// @inheritdoc IController
  uint256 public override liqBonusPercent;

  /// @inheritdoc IController
  uint256 public override ltvPercent;

  /// @inheritdoc IController
  mapping(address vault => mapping(address user => uint256 shares)) public override deposits;

  /// @inheritdoc IController
  mapping(address user => Borrowing borrowing) public override borrowings;

  mapping(address user => EnumerableSet.AddressSet vaults) private _vaults;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param osToken The address of the OsToken contract
   * @param keeper The address of the Keeper contract
   * @param vaultsRegistry The address of the VaultsRegistry contract
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(address osToken, address keeper, address vaultsRegistry) {
    _osToken = IOsToken(osToken);
    _keeper = IKeeperRewards(keeper);
    _vaultsRegistry = IVaultsRegistry(vaultsRegistry);
  }

  /// @inheritdoc IController
  function vaults(address user) public view override returns (address[] memory) {
    return _vaults[user].values();
  }

  /// @inheritdoc IController
  function getDepositedAssets(address user) public view override returns (uint256 assets) {
    address[] memory userVaults = vaults(user);
    address vault;
    for (uint256 i = 0; i < userVaults.length; ) {
      vault = userVaults[i];
      if (_keeper.isHarvestRequired(vault)) revert VaultNotHarvested();

      // sum all the user assets in different vaults
      assets += IVaultToken(vault).convertToAssets(deposits[vault][user]);

      unchecked {
        // cannot overflow as there are up to _maxVaultsCount vaults
        ++i;
      }
    }
  }

  /// @inheritdoc IController
  function deposit(address vault, uint256 shares) external override {
    if (!_vaultsRegistry.vaults(vault)) revert InvalidVault();
    if (shares == 0) revert InvalidShares();
    if (_vaults[msg.sender].length() >= maxVaultsCount) revert ExceededVaultsCount();

    // add vault to user vaults
    _vaults[msg.sender].add(vault);

    // increase user deposit in the vault
    deposits[vault][msg.sender] += shares;

    // transfer shares from the user to the controller
    SafeERC20.safeTransferFrom(IERC20(vault), msg.sender, address(this), shares);

    // emit event
    emit Deposit(msg.sender, vault, shares);
  }

  /// @inheritdoc IController
  function withdraw(
    address vault,
    address receiver,
    uint256 shares,
    bool redeemAndEnterExitQueue
  ) external override {
    if (receiver == address(0)) revert InvalidRecipient();
    if (shares == 0) revert InvalidShares();

    // get total amount of deposited shares
    uint256 depositedShares = deposits[vault][msg.sender];
    if (depositedShares == 0) revert InvalidVault();

    // clean up vault if all the shares were withdrawn
    if (shares == depositedShares) _vaults[msg.sender].remove(vault);

    // reduce number of deposited shares, reverts if not enough shares
    deposits[vault][msg.sender] = depositedShares - shares;

    // check user borrowings
    uint256 borrowedShares = syncBorrowing(msg.sender);
    if (borrowedShares > 0) {
      uint256 depositedAssets = getDepositedAssets(msg.sender);
      uint256 borrowedAssets = _osToken.convertToAssets(borrowedShares);

      // calculate and validate current health factor
      _checkHealthFactor(depositedAssets, borrowedAssets);

      // calculate and validate collateral needed for total borrowed amount
      _checkLtv(depositedAssets, borrowedAssets);
    }

    // transfer shares to the receiver
    _transferShares(vault, receiver, shares, redeemAndEnterExitQueue);

    // emit event
    emit Withdraw(msg.sender, vault, receiver, shares);
  }

  /// @inheritdoc IController
  function borrow(
    uint256 assets,
    address receiver,
    address referrer
  ) external override returns (uint256 shares) {
    if (assets == 0) revert InvalidAssets();
    if (receiver == address(0)) revert InvalidRecipient();

    // fetch user state
    uint256 depositedAssets = getDepositedAssets(msg.sender);
    uint256 borrowedShares = syncBorrowing(msg.sender);

    // mint shares to the receiver
    shares = _osToken.mintShares(receiver, assets);
    borrowedShares += shares;

    // calculate borrowed assets
    uint256 borrowedAssets = _osToken.convertToAssets(borrowedShares);

    // calculate and validate current health factor
    _checkHealthFactor(depositedAssets, borrowedAssets);

    // calculate and validate collateral needed for total borrowed amount
    _checkLtv(depositedAssets, borrowedAssets);

    // update borrowed shares amount
    Borrowing storage borrowing = borrowings[msg.sender];
    borrowing.shares = SafeCast.toUint128(borrowedShares);

    // emit event
    emit Borrow(msg.sender, receiver, assets, shares, referrer);
  }

  /// @inheritdoc IController
  function repay(uint128 shares) external override returns (uint256 assets) {
    if (shares == 0) revert InvalidShares();

    // sync borrowing and fetch borrowed shares
    uint256 borrowedShares = syncBorrowing(msg.sender);

    // update borrowed shares amount. Reverts if repaid more than borrowed.
    Borrowing storage borrowing = borrowings[msg.sender];
    borrowing.shares = SafeCast.toUint128(borrowedShares - shares);

    // burn osToken shares
    assets = _osToken.burnShares(msg.sender, shares);

    // emit event
    emit Repay(msg.sender, assets, shares);
  }

  /// @inheritdoc IController
  function liquidate(
    address user,
    uint256 coveredShares,
    address[] calldata sortedVaults,
    address collateralReceiver,
    bool redeemAndEnterExitQueue
  ) external override returns (uint256 coveredAssets) {
    if (collateralReceiver == address(0)) revert InvalidRecipient();
    if (sortedVaults.length != _vaults[user].length()) revert InvalidVaults();

    // sync borrowing and fetch borrowed shares
    uint256 borrowedShares = syncBorrowing(msg.sender);
    uint256 borrowedAssets = _osToken.convertToAssets(borrowedShares);
    uint256 depositedAssets = getDepositedAssets(msg.sender);

    // check health factor violation
    if (_getHealthFactor(depositedAssets, borrowedAssets) >= healthFactorLiqThreshold) {
      revert HealthFactorNotViolated();
    }

    // calculate assets to cover
    if (borrowedShares == coveredShares) {
      coveredAssets = borrowedAssets;
    } else {
      coveredShares = Math.min(borrowedShares, coveredShares);
      coveredAssets = _osToken.convertToAssets(coveredShares);
    }

    // calculate assets received by liquidator with bonus
    uint256 receivedAssets;
    unchecked {
      // cannot overflow as it is capped with underlying total supply
      receivedAssets = coveredAssets + Math.mulDiv(coveredAssets, liqBonusPercent, _maxPercent);
    }

    // adjust covered shares based on received assets
    if (receivedAssets > depositedAssets) {
      receivedAssets = depositedAssets;
      unchecked {
        // cannot underflow as liqBonusPercent <= _maxPercent
        coveredAssets =
          depositedAssets -
          Math.mulDiv(depositedAssets, liqBonusPercent, _maxPercent);
      }
      coveredShares = _osToken.convertToShares(coveredAssets);
    }

    // reduce osToken supply
    _osToken.burnShares(msg.sender, coveredShares);

    // execute liquidation
    _executeLiquidation(
      user,
      receivedAssets,
      sortedVaults,
      collateralReceiver,
      redeemAndEnterExitQueue
    );

    // emit event
    emit Liquidation(
      msg.sender,
      user,
      collateralReceiver,
      coveredShares,
      coveredAssets,
      receivedAssets
    );
  }

  /// @inheritdoc IController
  function syncBorrowing(address user) public override returns (uint256 borrowedShares) {
    Borrowing memory borrowing = borrowings[user];
    borrowedShares = borrowing.shares;

    // update osToken state and fetch new fee per asset
    _osToken.updateState();
    uint256 cumulativeFeePerAsset = _osToken.cumulativeFeePerAsset();

    // check whether fee is already up to date
    if (cumulativeFeePerAsset == borrowing.cumulativeFeePerAsset) return borrowedShares;

    uint256 borrowedAssets = _osToken.convertToAssets(borrowedShares);
    if (borrowedAssets == 0) {
      // nothing is borrowed, checkpoint current cumulativeFeePerAsset
      borrowings[user].cumulativeFeePerAsset = SafeCast.toUint128(cumulativeFeePerAsset);
    } else {
      // add treasury fee to borrowed shares
      borrowedShares += _calculateTreasuryFee(
        borrowing.cumulativeFeePerAsset,
        cumulativeFeePerAsset,
        borrowedAssets
      );

      // update state
      borrowings[user] = Borrowing({
        shares: SafeCast.toUint128(borrowedShares),
        cumulativeFeePerAsset: SafeCast.toUint128(cumulativeFeePerAsset)
      });
    }
  }

  /**
   * @notice Internal function for calculating treasury fee
   * @param prevCumulativeFeePerAsset The previous cumulative fee per asset
   * @param newCumulativeFeePerAsset The new cumulative fee per asset
   * @param borrowedAssets The number of borrowed assets
   * @return shares The calculated treasury fee shares
   */
  function _calculateTreasuryFee(
    uint256 prevCumulativeFeePerAsset,
    uint256 newCumulativeFeePerAsset,
    uint256 borrowedAssets
  ) private view returns (uint256 shares) {
    uint256 feeAssets = Math.mulDiv(
      newCumulativeFeePerAsset - prevCumulativeFeePerAsset,
      borrowedAssets,
      _wad
    );
    return _osToken.convertToShares(feeAssets);
  }

  /**
   * @notice Internal function for getting the health factor
   * @param depositedAssets The number of deposited assets
   * @param borrowedAssets The number of borrowed assets
   * @return The calculated health factor
   */
  function _getHealthFactor(
    uint256 depositedAssets,
    uint256 borrowedAssets
  ) private view returns (uint256) {
    return Math.mulDiv(depositedAssets * _wad, liqThresholdPercent, borrowedAssets * _maxPercent);
  }

  /**
   * @notice Internal function for checking the health factor. Reverts if it is lower than threshold.
   * @param depositedAssets The number of deposited assets
   * @param borrowedAssets The number of borrowed assets
   */
  function _checkHealthFactor(uint256 depositedAssets, uint256 borrowedAssets) private view {
    if (borrowedAssets == 0) return;
    if (healthFactorLiqThreshold > _getHealthFactor(depositedAssets, borrowedAssets)) {
      revert LowHealthFactor();
    }
  }

  /**
   * @notice Internal function for checking the LTV. Reverts if it is low.
   * @param depositedAssets The number of deposited assets
   * @param borrowedAssets The number of borrowed assets
   */
  function _checkLtv(uint256 depositedAssets, uint256 borrowedAssets) private view {
    uint256 requiredAssets = Math.mulDiv(borrowedAssets, ltvPercent, _maxPercent);
    if (requiredAssets > depositedAssets) revert LowLtv();
  }

  /**
   * @notice Internal function for executing liquidation
   * @param user The user address to liquidate
   * @param totalAssets The total number of assets to pay
   * @param sortedVaults The list of vaults that is sorted by the withdrawal priority
   * @param receiver The address of the vault tokens receiver
   * @param redeemAndEnterExitQueue Whether to redeem and send vault tokens to the exit queue
   */
  function _executeLiquidation(
    address user,
    uint256 totalAssets,
    address[] calldata sortedVaults,
    address receiver,
    bool redeemAndEnterExitQueue
  ) private {
    address vault;
    uint256 userAssets;
    uint256 userShares;
    uint256 paymentAssets;
    uint256 paymentShares;
    uint256 leftShares;
    for (uint256 i = 0; i < sortedVaults.length; ) {
      // no need to check for harvest as it's checked at getDepositedAssets
      vault = sortedVaults[i];

      // fetch user vault shares and assets
      userShares = deposits[vault][user];
      // if no user shares, either user has provided invalid vault or all shares are already withdrawn
      if (userShares == 0) revert InvalidVault();
      userAssets = IVaultToken(vault).convertToAssets(userShares);

      // calculate shares and assets to pay
      if (userAssets <= totalAssets) {
        // all user shares are paid
        paymentAssets = userAssets;
        paymentShares = userShares;
      } else {
        // only part of user shares are paid
        paymentAssets = totalAssets;
        paymentShares = IVaultToken(vault).convertToShares(paymentAssets);
      }

      unchecked {
        // cannot underflow as totalAssets >= paymentAssets
        totalAssets -= paymentAssets;
      }

      // clean up vault if all the shares are withdrawn, ignore rounding error
      leftShares = userShares - paymentShares;
      if (leftShares <= 1) {
        // clean up position
        _vaults[user].remove(vault);
        delete deposits[vault][user];
      } else {
        // update user deposit balance
        deposits[vault][user] = leftShares;
      }

      // transfer shares to the receiver
      _transferShares(vault, receiver, paymentShares, redeemAndEnterExitQueue);

      // all the needed assets withdrawn
      if (totalAssets == 0) break;

      unchecked {
        // cannot overflow as there are up to _maxVaultsCount vaults
        ++i;
      }
    }
    // should never reach here
    if (totalAssets != 0) revert FailedToLiquidate();
  }

  /**
   * @notice Internal function for transferring shares to the receiver
   * @param vault The address of the Vault
   * @param receiver The address of the shares receiver
   * @param shares The number of shares to transfer
   * @param redeemAndEnterExitQueue Whether to redeem and send vault tokens to the exit queue
   */
  function _transferShares(
    address vault,
    address receiver,
    uint256 shares,
    bool redeemAndEnterExitQueue
  ) private {
    if (redeemAndEnterExitQueue) {
      // submit shares to the exit queue. Exit queue ID can be obtained from the Vault's event
      IVaultEnterExit(vault).redeemAndEnterExitQueue(shares, receiver, address(this));
    } else {
      // transfer shares to the receiver
      SafeERC20.safeTransferFrom(IERC20(vault), address(this), receiver, shares);
    }
  }
}
