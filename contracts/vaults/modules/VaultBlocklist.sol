// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IVaultBlocklist} from '../../interfaces/IVaultBlocklist.sol';
import {Errors} from '../../libraries/Errors.sol';
import {VaultAdmin} from './VaultAdmin.sol';

/**
 * @title VaultBlocklist
 * @author StakeWise
 * @notice Defines the functionality for blocking addresses for the Vault
 */
abstract contract VaultBlocklist is Initializable, VaultAdmin, IVaultBlocklist {
  /// @inheritdoc IVaultBlocklist
  address public override blocklistManager;

  /// @inheritdoc IVaultBlocklist
  mapping(address => bool) public override blockedAccounts;

  /// @inheritdoc IVaultBlocklist
  function updateBlocklist(address account, bool blocked) public virtual override {
    if (msg.sender != blocklistManager) revert Errors.AccessDenied();
    _updateBlocklist(account, blocked);
  }

  /// @inheritdoc IVaultBlocklist
  function setBlocklistManager(address _blocklistManager) external override {
    _checkAdmin();
    _setBlocklistManager(_blocklistManager);
  }

  /**
   * @notice Internal function for checking blocklist
   * @param account The address of the account to check
   */
  function _checkBlocklist(address account) internal view {
    if (blockedAccounts[account]) revert Errors.AccessDenied();
  }

  /**
   * @notice Internal function for updating blocklist
   * @param account The address of the account to update
   * @param blocked Defines whether account is added to the blocklist or removed
   */
  function _updateBlocklist(address account, bool blocked) private {
    if (blockedAccounts[account] == blocked) return;
    blockedAccounts[account] = blocked;
    emit BlocklistUpdated(msg.sender, account, blocked);
  }

  /**
   * @dev Internal function for updating the blocklist manager externally or from the initializer
   * @param _blocklistManager The address of the new blocklist manager
   */
  function _setBlocklistManager(address _blocklistManager) private {
    // update blocklist manager address
    blocklistManager = _blocklistManager;
    emit BlocklistManagerUpdated(msg.sender, _blocklistManager);
  }

  /**
   * @dev Initializes the VaultBlocklist contract
   * @param _blocklistManager The address of the blocklist manager
   */
  function __VaultBlocklist_init(address _blocklistManager) internal onlyInitializing {
    _setBlocklistManager(_blocklistManager);
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
