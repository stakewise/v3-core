// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.18;

import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

contract Controller {
  using EnumerableSet for EnumerableSet.AddressSet;

  mapping(address => EnumerableSet.AddressSet) private _vaults;
  mapping(address => mapping(address => uint256)) private _suppliedShares;
  mapping(address => uint256) public override borrowedShares;

  /// @inheritdoc IController
  function supply(address vault, uint256 shares) external override {
    if (shares == 0) revert InvalidShares();
    if (!vaultsRegistry.vaults(vault)) revert InvalidVault();
    if (_vaults[msg.sender].length >= _maxVaultsCount) revert ExceededVaultsCount();

    _vaults[msg.sender].add(vault);

    unchecked {
      // cannot overflow as it is capped with vault's total supply
      _suppliedShares[vault][msg.sender] += shares;
    }

    SafeERC20.safeTransferFrom(IERC20(vault), msg.sender, address(this), shares);

    emit Supplied(msg.sender, vault, shares);
  }

  /// @inheritdoc IController
  function withdraw(address vault, address receiver, uint256 shares) external override {
    // validate receiver
    if (receiver == address(0)) revert InvalidRecipient();

    // get total amount of supplied shares
    uint256 suppliedShares = _suppliedShares[vault][msg.sender];
    if (suppliedShares == 0) revert InvalidVault();

    // clean up vault if all the shares are withdrawn
    if (shares == suppliedShares) _vaults[msg.sender].remove(vault);

    // reduce number of supplied shares, reverts if not enough shares
    _suppliedShares[vault][msg.sender] = suppliedShares - shares;

    uint256 borrowedShares = _borrowedShares[msg.sender];
    if (borrowedShares > 0) {
      uint256 suppliedAssets = getSuppliedAssets(msg.sender);
      uint256 borrowedAssets = osToken.convertToAssets(borrowedShares);

      // calculate and validate current health factor
      _checkHealthFactor(suppliedAssets, borrowedAssets);

      // calculate and validate collateral needed for total borrowed amount
      _checkLtv(suppliedAssets, borrowedAssets);
    }

    // transfer shares to the receiver
    SafeERC20.safeTransferFrom(IERC20(vault), address(this), receiver, shares);

    // emit event
    emit Withdrawn(msg.sender, vault, receiver, shares);
  }

  /// @inheritdoc IController
  function borrow(
    uint256 assets,
    address receiver,
    address referrer
  ) external override returns (uint256 shares) {
    if (!vaultsRegistry.vaults(vault)) revert InvalidVault();
    if (receiver == address(0)) revert InvalidRecipient();

    // fetch user state
    uint256 suppliedAssets = getSuppliedAssets(msg.sender);
    uint256 borrowedShares = _borrowedShares[msg.sender];
    uint256 borrowedAssets = osToken.convertToAssets(borrowedShares);

    // calculate and validate current health factor
    _checkHealthFactor(suppliedAssets, borrowedAssets);

    // calculate and validate collateral needed for total borrowed amount
    _checkLtv(suppliedAssets, borrowedAssets);

    // mint shares to the receiver
    shares = osToken.mintShares(receiver, assets);

    // update borrowed shares amount
    unchecked {
      // cannot overflow as borrowed shares are capped by osToken total supply
      _borrowedShares[msg.sender] = borrowedShares + shares;
    }

    // emit event
    emit Borrowed(msg.sender, receiver, assets, shares, referrer);
  }

  /// @inheritdoc IController
  function repay(uint256 shares) external override returns (uint256 assets) {
    // fetch user state
    uint256 borrowedShares = _borrowedShares[msg.sender];

    // burn osToken shares
    assets = osToken.burnShares(msg.sender, shares);

    // update borrowed shares amount. Reverts if repaid more than borrowed.
    _borrowedShares[msg.sender] = borrowedShares - shares;

    // emit event
    emit Repaid(msg.sender, assets, shares);
  }

  /// @inheritdoc IController
  function liquidate(
    address user,
    uint256 coveredShares,
    address collateralReceiver,
    bool enterExitQueue
  ) external override returns (uint256 coveredAssets) {
    if (!vaultsRegistry.vaults(vault)) revert InvalidVault();

    // calculate health factor
    uint256 borrowedShares = _borrowedShares[user];
    uint256 borrowedAssets = osToken.convertToAssets(borrowedShares);
    uint256 suppliedAssets = getSuppliedAssets(user);
    if (_getHealthFactor(suppliedAssets, borrowedAssets) >= healthFactorLiqThreshold) {
      revert HealthFactorNotViolated();
    }

    // calculate assets to cover
    if (borrowedShares == coveredShares) {
      coveredAssets = borrowedAssets;
    } else {
      coveredShares = Math.min(borrowedShares, coveredShares);
      coveredAssets = osToken.convertToAssets(coveredShares);
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
      coveredShares = osToken.convertToShares(coveredAssets);
    }

    // reduce osToken supply
    osToken.burnShares(msg.sender, coveredShares);

    // execute liquidation
    _executePayment(user, receivedAssets, collateralReceiver, enterExitQueue);

    // emit event
    emit Liquidation(
      msg.sender,
      user,
      coveredShares,
      coveredAssets,
      collateralReceiver,
      receivedAssets,
      enterExitQueue
    );
  }

  function updateVaultState() external;

  function updateTreasuryFee(address user) public override {
    // 1. update osToken state
    // 2. assets = osToken.convertToAssets(borrowedShares)
    // 3. feeAssets = Math.mulDiv(abs(assets - prevAssets), feePercent, 10000)
    // 4. borrowedShares += osToken.convertToShares(feeAssets)
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
      userShares = _balances[vault][user];

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

  /// @inheritdoc IController
  function getSuppliedAssets(address user) public view override returns (uint256 assets) {
    address[] memory vaults = _vaults[user].values();
    address vault;
    for (uint256 i = 0; i < vaults.length; ) {
      vault = vaults[i];
      if (keeper.isHarvestRequired(vault)) revert VaultNotHarvested();

      assets += IVault(vault).convertToAssets(_balances[vault][user]);

      unchecked {
        // cannot overflow as there are up to _maxVaultsCount vaults
        ++i;
      }
    }
  }

  function _getHealthFactor(
    uint256 suppliedAssets,
    uint256 borrowedAssets
  ) private view returns (uint256) {
    return Math.mulDiv(suppliedAssets * liqThresholdPercent, _wad, borrowedAssets * _maxPercent);
  }

  function _checkHealthFactor(uint256 suppliedAssets, uint256 borrowedAssets) private view {
    if (borrowedAssets == 0) return;
    if (healthFactorLiqThreshold > _getHealthFactor(suppliedAssets, borrowedAssets)) {
      revert LowHealthFactor();
    }
  }

  function _checkLtv(uint256 suppliedAssets, uint256 borrowedAssets) private view {
    uint256 requiredAssets = Math.mulDiv(borrowedAssets, ltvPercent, _maxPercent);
    if (requiredAssets > suppliedAssets) revert NotEnoughSuppliedAssets();
  }
}
