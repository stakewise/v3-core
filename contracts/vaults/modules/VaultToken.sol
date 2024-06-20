// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IVaultToken} from '../../interfaces/IVaultToken.sol';
import {Errors} from '../../libraries/Errors.sol';
import {ERC20Upgradeable} from '../../base/ERC20Upgradeable.sol';
import {VaultState} from './VaultState.sol';

/**
 * @title VaultToken
 * @author StakeWise
 * @notice Defines the token functionality for the Vault
 */
abstract contract VaultToken is Initializable, ERC20Upgradeable, VaultState, IVaultToken {
  /// @inheritdoc IERC20
  function totalSupply() external view override returns (uint256) {
    return _totalShares;
  }

  /// @inheritdoc IERC20
  function balanceOf(address account) external view returns (uint256) {
    return _balances[account];
  }

  /// @inheritdoc VaultState
  function _mintShares(address owner, uint256 shares) internal virtual override {
    super._mintShares(owner, shares);
    emit Transfer(address(0), owner, shares);
  }

  /// @inheritdoc VaultState
  function _burnShares(address owner, uint256 shares) internal virtual override {
    super._burnShares(owner, shares);
    emit Transfer(owner, address(0), shares);
  }

  /// @inheritdoc ERC20Upgradeable
  function _transfer(address from, address to, uint256 amount) internal virtual override {
    if (from == address(0) || to == address(0)) revert Errors.ZeroAddress();
    _balances[from] -= amount;

    // Cannot overflow because the sum of all user
    // balances can't exceed the max uint256 value
    unchecked {
      _balances[to] += amount;
    }

    emit Transfer(from, to, amount);
  }

  /**
   * @dev Initializes the VaultToken contract
   * @param _name The name of the ERC20 token
   * @param _symbol The symbol of the ERC20 token
   */
  function __VaultToken_init(string memory _name, string memory _symbol) internal onlyInitializing {
    if (bytes(_name).length > 30 || bytes(_symbol).length > 10) revert Errors.InvalidTokenMeta();

    // initialize ERC20Permit
    __ERC20Upgradeable_init(_name, _symbol);
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
