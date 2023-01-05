// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {IERC20} from '../../interfaces/IERC20.sol';
import {IKeeperRewards} from '../../interfaces/IKeeperRewards.sol';
import {IVaultToken} from '../../interfaces/IVaultToken.sol';
import {ERC20Upgradeable} from '../../base/ERC20Upgradeable.sol';
import {VaultImmutables} from './VaultImmutables.sol';

/**
 * @title VaultToken
 * @author StakeWise
 * @notice Defines the token functionality for the Vault
 */
abstract contract VaultToken is VaultImmutables, Initializable, ERC20Upgradeable, IVaultToken {
  /// @inheritdoc IVaultToken
  uint256 public override capacity;

  uint128 internal _totalShares;
  uint128 internal _totalAssets;

  /// @inheritdoc IERC20
  function totalSupply() external view returns (uint256) {
    return _totalShares;
  }

  /// @inheritdoc IVaultToken
  function totalAssets() external view override returns (uint256) {
    return _totalAssets;
  }

  /// @inheritdoc IVaultToken
  function convertToShares(uint256 assets) public view override returns (uint256 shares) {
    return _convertToShares(assets, Math.Rounding.Down);
  }

  /// @inheritdoc IVaultToken
  function convertToAssets(uint256 shares) public view override returns (uint256 assets) {
    uint256 totalShares = _totalShares;
    return (totalShares == 0) ? shares : Math.mulDiv(shares, _totalAssets, totalShares);
  }

  /**
   * @dev Internal function for retrieving the total assets stored in the Vault
   * @return The total amount of assets stored in the Vault
   */
  function _vaultAssets() internal view virtual returns (uint256);

  /**
   * @dev Internal function for transferring assets from the Vault to the receiver
   * @dev IMPORTANT: because control is transferred to the receiver, care must be
   *    taken to not create reentrancy vulnerabilities. The Vault must follow the checks-effects-interactions pattern:
   *    https://docs.soliditylang.org/en/v0.8.17/security-considerations.html#use-the-checks-effects-interactions-pattern
   * @param receiver The address that will receive the assets
   * @param assets The number of assets to transfer
   */
  function _transferVaultAssets(address receiver, uint256 assets) internal virtual;

  /**
   * @dev Internal conversion function (from assets to shares) with support for rounding direction.
   */
  function _convertToShares(
    uint256 assets,
    Math.Rounding rounding
  ) internal view returns (uint256 shares) {
    uint256 totalShares = _totalShares;
    // Will revert if assets > 0, totalShares > 0 and _totalAssets = 0.
    // That corresponds to a case where any asset would represent an infinite amount of shares.
    return
      (assets == 0 || totalShares == 0)
        ? assets
        : Math.mulDiv(assets, totalShares, _totalAssets, rounding);
  }

  /**
   * @dev Initializes the VaultToken contract
   * @param _name The name of the ERC20 token
   * @param _symbol The symbol of the ERC20 token
   * @param _capacity The amount after which the Vault stops accepting deposits
   */
  function __VaultToken_init(
    string memory _name,
    string memory _symbol,
    uint256 _capacity
  ) internal onlyInitializing {
    // initialize ERC20Permit
    __ERC20Upgradeable_init(_name, _symbol);
    capacity = _capacity;
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
