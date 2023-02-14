// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

contract Controller {
  using EnumerableSet for EnumerableSet.AddressSet;

  mapping(address => EnumerableSet.AddressSet) private _vaults;
  mapping(address => mapping(address => uint256)) private _suppliedShares;
  mapping(address => uint256) public override borrowedShares;

  /// @inheritdoc IController
  function supply(address vault, uint256 shares, uint16 referralCode) external override {
    if (shares == 0) revert InvalidShares();
    if (!vaultsRegistry.vaults(vault)) revert InvalidVault();
    if (_vaults[msg.sender].length >= _maxVaultsCount) revert ExceededVaultsCount();

    _vaults[msg.sender].add(vault);

    unchecked {
      // cannot overflow as it is capped with vault's total supply
      _suppliedShares[vault][msg.sender] += shares;
    }

    SafeERC20.safeTransferFrom(IERC20(vault), msg.sender, address(this), shares);

    emit Supplied(msg.sender, vault, shares, referralCode);
  }

  /// @inheritdoc IController
  function withdraw(address vault, address receiver, uint256 shares) external override {
    // validate receiver
    if (receiver == address(0)) revert InvalidRecipient();

    // get total amount of supplied shares
    uint256 suppliedShares = _suppliedShares[vault][msg.sender];
    if (suppliedShares == 0) revert InvalidVault();

    // check whether all shares must be withdrawn
    if (shares == type(uint256).max) shares = suppliedShares;

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

      // calculate and check collateral needed for total borrowed amount
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
    uint16 referralCode
  ) external override returns (uint256 shares) {
    if (!vaultsRegistry.vaults(vault)) revert InvalidVault();
    if (receiver == address(0)) revert InvalidRecipient();

    // fetch user state
    uint256 suppliedAssets = getSuppliedAssets(msg.sender);
    uint256 borrowedShares = _borrowedShares[msg.sender];
    uint256 borrowedAssets = osToken.convertToAssets(borrowedShares);

    // calculate and validate current health factor
    _checkHealthFactor(suppliedAssets, borrowedAssets);

    // calculate and check collateral needed for total borrowed amount
    _checkLtv(suppliedAssets, borrowedAssets);

    // mint shares to the receiver
    shares = osToken.mintShares(receiver, assets);

    // update borrowed shares amount
    unchecked {
      // cannot overflow as borrowed shares are capped by osToken total supply
      _borrowedShares[msg.sender] = borrowedShares + shares;
    }

    // emit event
    emit Borrowed(msg.sender, receiver, assets, shares, referralCode);
  }

  /// @inheritdoc IController
  function repay(uint256 shares) external override returns (uint256 assets) {
    // fetch user state
    uint256 borrowedShares = _borrowedShares[msg.sender];

    // check whether all shares must be repaid
    if (shares == type(uint256).max) shares = borrowedShares;

    // transfer shares to controller
    SafeERC20.safeTransferFrom(IERC20(osToken), msg.sender, address(this), shares);

    // burn osToken shares
    assets = osToken.burnShares(shares);

    // update borrowed shares amount
    _borrowedShares[msg.sender] = borrowedShares - shares;

    // emit event
    emit Repaid(msg.sender, assets, shares);
  }

  /// @inheritdoc IController
  function liquidate(uint256 shares) external override returns (uint256 assets) {
    if (!vaultsRegistry.vaults(vault)) revert InvalidVault();

    // fetch user state
    uint256 borrowedShares = _borrowedShares[msg.sender];

    // check whether all shares must be repaid
    if (shares == type(uint256).max) shares = borrowedShares;

    // transfer shares to controller
    SafeERC20.safeTransferFrom(IERC20(osToken), msg.sender, address(this), shares);

    // burn osToken shares
    assets = osToken.burnShares(shares);

    // update borrowed shares amount
    _borrowedShares[msg.sender] = borrowedShares - shares;

    // emit event
    emit Repaid(msg.sender, assets, shares);
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

  function _checkHealthFactor(uint256 suppliedAssets, uint256 borrowedAssets) private view {
    if (borrowedAssets == 0) return;
    uint256 hf = Math.mulDiv(
      suppliedAssets * liqThresholdPercent,
      _wad,
      borrowedAssets * _maxPercent
    );
    if (_healthFactorLiqThreshold > hf) revert LowHealthFactor();
  }

  function _checkLtv(uint256 suppliedAssets, uint256 borrowedAssets) private view {
    uint256 requiredAssets = Math.mulDiv(borrowedAssets, ltvPercent, _maxPercent);
    if (requiredAssets > suppliedAssets) revert NotEnoughSuppliedAssets();
  }
}
