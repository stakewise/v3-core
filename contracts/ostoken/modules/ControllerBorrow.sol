// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.18;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {Ownable2StepUpgradeable} from '@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {VaultsSorting} from '../../libraries/VaultsSorting.sol';
import {IControllerBorrow} from '../../interfaces/IControllerBorrow.sol';
import {IVaultToken} from '../../interfaces/IVaultToken.sol';
import {ControllerImmutables} from './ControllerImmutables.sol';

/**
 * @title ControllerBorrow
 * @author StakeWise
 * @notice Defines the OsToken controller borrowing functionality
 */
abstract contract ControllerBorrow is
  Initializable,
  Ownable2StepUpgradeable,
  ControllerImmutables,
  IControllerBorrow
{
  using EnumerableSet for EnumerableSet.AddressSet;

  uint256 internal constant _maxPercent = 10_000; // @dev 100.00 %
  uint256 internal constant _wad = 1e18;
  uint256 internal constant _maxVaultsCount = 10;

  /// @inheritdoc IControllerBorrow
  mapping(address => BorrowPosition) public override borrowings;

  uint256 internal liqThresholdPercent;
  uint256 internal healthFactorLiqThreshold;
  uint256 internal ltvPercent;
  uint256 internal liqBonusPercent;

  mapping(address => uint256) internal _treasuryShares;
  mapping(address => EnumerableSet.AddressSet) internal _vaults;
  mapping(address => mapping(address => uint256)) internal _suppliedShares;

  function supply(address vault, uint256 shares) external {
    if (shares == 0) revert InvalidShares();
    if (!_vaultsRegistry.vaults(vault)) revert InvalidVault();
    if (_vaults[msg.sender].length() >= _maxVaultsCount) revert ExceededVaultsCount();

    // fetch user position
    BorrowPosition memory position = borrowings[msg.sender];
    if (position.shares > 0) _updateSuppliedAssets(msg.sender, position);

    _vaults[msg.sender].add(vault);

    unchecked {
      // cannot overflow as it is capped with vault's total supply
      _suppliedShares[vault][msg.sender] += shares;
    }

    SafeERC20.safeTransferFrom(IERC20(vault), msg.sender, address(this), shares);

    //    emit Supplied(msg.sender, vault, shares);
  }

  function withdraw(address vault, address receiver, uint256 shares) external {
    // validate receiver
    if (receiver == address(0)) revert InvalidRecipient();

    // fetch user position
    BorrowPosition memory position = borrowings[msg.sender];
    uint256 suppliedAssets;
    if (position.shares > 0) {
      suppliedAssets = _updateSuppliedAssets(msg.sender, position);
    }

    // get total amount of supplied shares
    uint256 suppliedShares = _suppliedShares[vault][msg.sender];
    if (suppliedShares == 0) revert InvalidVault();

    // clean up vault if all the shares are withdrawn
    if (shares == suppliedShares) _vaults[msg.sender].remove(vault);

    // reduce number of supplied shares, reverts if not enough shares
    _suppliedShares[vault][msg.sender] = suppliedShares - shares;

    if (position.shares > 0) {
      unchecked {
        // cannot underflow as suppliedAssets is a sum of user's assets
        suppliedAssets -= IVaultToken(vault).convertToAssets(shares);
      }
      uint256 borrowedAssets = _osToken.convertToAssets(position.shares);

      // calculate and validate current health factor
      _checkHealthFactor(suppliedAssets, borrowedAssets);

      // calculate and validate collateral needed for total borrowed amount
      _checkLtv(suppliedAssets, borrowedAssets);
    }

    // transfer shares to the receiver
    SafeERC20.safeTransferFrom(IERC20(vault), address(this), receiver, shares);

    // emit event
    //    emit Withdrawn(msg.sender, vault, receiver, shares);
  }

  /// @inheritdoc IControllerBorrow
  function borrow(
    uint256 assets,
    address receiver,
    address referrer
  ) external override returns (uint256 shares) {
    if (receiver == address(0)) revert InvalidRecipient();

    // fetch user position
    BorrowPosition memory position = borrowings[msg.sender];

    // mint shares to the receiver
    shares = _osToken.mintShares(receiver, assets);

    // update and fetch supplied assets
    uint256 suppliedAssets = _updateSuppliedAssets(msg.sender, position);

    // update position with new shares
    unchecked {
      // cannot overflow as borrowed shares are capped by OsToken total supply
      position.shares += SafeCast.toUint128(shares);
    }

    // calculate user borrowed assets
    uint256 borrowedAssets = _osToken.convertToAssets(position.shares);

    // validate collateral needed for total borrowed amount
    _checkLtv(suppliedAssets, borrowedAssets);

    // validate current health factor
    _checkHealthFactor(suppliedAssets, borrowedAssets);

    // update position
    borrowings[msg.sender] = position;

    // emit event
    emit Borrowed(msg.sender, receiver, assets, shares, referrer);
  }

  /// @inheritdoc IControllerBorrow
  function repay(uint128 shares) external override returns (uint256 assets) {
    // fetch user position
    BorrowPosition memory position = borrowings[msg.sender];

    // burn osToken shares
    assets = _osToken.burnShares(msg.sender, shares);

    // update and fetch supplied assets
    _updateSuppliedAssets(msg.sender, position);

    // update borrowed shares amount. Reverts if repaid more than borrowed.
    position.shares -= shares;

    // update position
    borrowings[msg.sender] = position;

    // emit event
    emit Repaid(msg.sender, assets, shares);
  }

  function liquidate(
    address user,
    uint256 coveredShares,
    address collateralReceiver,
    bool enterExitQueue
  ) external override returns (uint256 coveredAssets) {
    // fetch user position
    BorrowPosition memory position = borrowings[user];

    // calculate health factor
    uint256 suppliedAssets = _updateSuppliedAssets(user, position);
    uint256 borrowedAssets = _osToken.convertToAssets(position.shares);
    if (_getHealthFactor(suppliedAssets, borrowedAssets) >= healthFactorLiqThreshold) {
      revert HealthFactorNotViolated();
    }

    // calculate assets to cover
    if (position.shares == coveredShares) {
      coveredAssets = borrowedAssets;
    } else {
      coveredShares = Math.min(position.shares, coveredShares);
      coveredAssets = _osToken.convertToAssets(coveredShares);
    }

    // calculate assets received by liquidator with bonus
    uint256 receivedAssets;
    unchecked {
      // cannot overflow as it is capped with underlying total supply
      receivedAssets = coveredAssets + Math.mulDiv(coveredAssets, liqBonusPercent, _maxPercent);
    }

    // adjust covered shares based on received assets
    if (receivedAssets > suppliedAssets) {
      receivedAssets = suppliedAssets;
      unchecked {
        // cannot underflow as liqBonusPercent <= _maxPercent
        coveredAssets = suppliedAssets - Math.mulDiv(suppliedAssets, liqBonusPercent, _maxPercent);
      }
      coveredShares = _osToken.convertToShares(coveredAssets);
    }

    // reduce osToken supply
    _osToken.burnShares(msg.sender, coveredShares);

    // execute liquidation
    _executePayment(user, receivedAssets, collateralReceiver, enterExitQueue);

    // emit event
    //    emit Liquidation(
    //      msg.sender,
    //      user,
    //      coveredShares,
    //      coveredAssets,
    //      collateralReceiver,
    //      receivedAssets,
    //      enterExitQueue
    //    );
  }

  function _executePayment(
    address user,
    uint256 totalAssets,
    address receiver,
    bool enterExitQueue
  ) internal {
    address[] memory vaults = _vaults[user].values();
    address vault;
    uint256 userShares;
    uint256 paymentShares;
    for (uint256 i = 0; i < vaults.length; ) {
      // no need to check for harvest as it's checked at getSuppliedAssets
      vault = vaults[i];

      // fetch user shares
      userShares = _suppliedShares[vault][user];

      // calculate shares to pay
      paymentShares = IVault(vault).convertToShares(
        Math.min(IVault(vault).convertToAssets(userShares), totalAssets)
      );

      // clean up vault if all the shares are withdrawn
      if (userShares == paymentShares) _vaults[user].remove(vault);

      // update user supply balance
      unchecked {
        // cannot underflow as userShares >= paymentShares
        _balances[vault][user] = userShares - paymentShares;
      }

      if (enterExitQueue) {
        // submit shares to the exit queue. Exit queue ID can be obtained from the Vault's event
        IVault(vault).enterExitQueue(paymentShares, receiver, address(this));
      } else {
        SafeERC20.safeTransferFrom(IERC20(vault), address(this), receiver, paymentShares);
      }

      unchecked {
        // cannot overflow as there are up to _maxVaultsCount vaults
        ++i;
      }
    }
  }

  /**
   * @notice Internal function for calculating health factor
   * @param suppliedAssets The total amount of supplied assets
   * @param borrowedAssets The total amount of borrowed assets
   */
  function _getHealthFactor(
    uint256 suppliedAssets,
    uint256 borrowedAssets
  ) internal view returns (uint256) {
    return Math.mulDiv(suppliedAssets * liqThresholdPercent, _wad, borrowedAssets * _maxPercent);
  }

  /**
   * @notice Internal function for checking health factor. Reverts if not lower than required.
   * @param suppliedAssets The total amount of supplied assets
   * @param borrowedAssets The total amount of borrowed assets
   */
  function _checkHealthFactor(uint256 suppliedAssets, uint256 borrowedAssets) internal view {
    if (borrowedAssets == 0) return;
    if (healthFactorLiqThreshold > _getHealthFactor(suppliedAssets, borrowedAssets)) {
      revert LowHealthFactor();
    }
  }

  /**
   * @notice Internal function for checking LTV. Reverts if not enough supply assets.
   * @param suppliedAssets The total amount of supplied assets
   * @param borrowedAssets The total amount of borrowed assets
   */
  function _checkLtv(uint256 suppliedAssets, uint256 borrowedAssets) internal view {
    if (Math.mulDiv(borrowedAssets, ltvPercent, _maxPercent) > suppliedAssets) {
      revert NotEnoughSuppliedAssets();
    }
  }

  /**
   * @notice Internal function for calculating treasury fee of the position
   * @param position The borrow position of the user
   * @return assets The treasury fee assets
   */
  function _getTreasuryFee(BorrowPosition memory position) internal view returns (uint256 assets) {
    if (position.shares == 0) return 0;

    uint256 currentAssets = _osToken.convertToAssets(position.shares);
    if (currentAssets <= position.checkpointAssets) return 0;

    // fetch current fee percent
    uint256 feePercent = _osToken.feePercent();

    // calculate treasury new assets
    unchecked {
      uint256 assetsBeforeFee = Math.mulDiv(
        // cannot underflow as currentAssets > position.checkpointAssets
        currentAssets - position.checkpointAssets,
        // cannot overflow as feePercent <= _maxPercent
        _maxPercent + feePercent,
        _maxPercent
      );
      assets = Math.mulDiv(assetsBeforeFee, feePercent, _maxPercent);
    }
  }

  /**
   * @notice Internal function for updating and fetching user supplied assets
   * @param user The address of the user
   * @param userPosition The borrow position of the user
   * @return suppliedAssets The total user's supplied assets amount
   */
  function _updateSuppliedAssets(
    address user,
    BorrowPosition memory userPosition
  ) internal returns (uint256 suppliedAssets) {
    VaultsSorting.Vault[] memory vaults = VaultsSorting.sortByTotalAssets(_vaults[user].values());

    // calculate accumulated OsToken fee
    uint256 treasuryFeeAssets = _getTreasuryFee(userPosition);

    // iterate over all the user vaults
    address vault;
    uint256 userShares;
    uint256 userAssets;
    uint256 treasuryShares;
    uint256 treasuryAssets;
    for (uint256 i = 0; i < vaults.length; ) {
      vault = vaults[i].vault;

      // check vault is harvested
      if (_keeper.isHarvestRequired(vault)) revert VaultNotHarvested();

      // retrieve user shares and assets
      userShares = _suppliedShares[vault][user];
      userAssets = IVaultToken(vault).convertToAssets(userShares);

      if (treasuryFeeAssets > 0) {
        // calculate treasury shares and assets
        treasuryAssets = Math.min(userAssets, treasuryFeeAssets);
        treasuryShares = IVaultToken(vault).convertToShares(treasuryAssets);

        // update state
        unchecked {
          // cannot underflow as treasuryFeeAssets >= treasuryAssets
          treasuryFeeAssets -= treasuryAssets;
          // cannot underflow as userAssets >= treasuryAssets
          userAssets -= treasuryAssets;

          // update user supply shares
          // cannot underflow as userShares >= treasuryShares
          _suppliedShares[vault][user] = userShares - treasuryShares;
          // cannot overflow as it is capped with vault's total supply
          _treasuryShares[vault] += treasuryShares;
        }
      }

      unchecked {
        // cannot overflow as it is capped with underlying asset total supply
        suppliedAssets += userAssets;
        // cannot overflow as there are up to _maxVaultsCount vaults
        ++i;
      }
    }
  }
}
