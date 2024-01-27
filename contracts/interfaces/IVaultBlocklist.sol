// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {IVaultAdmin} from './IVaultAdmin.sol';

/**
 * @title IVaultBlocklist
 * @author StakeWise
 * @notice Defines the interface for the VaultBlocklist contract
 */
interface IVaultBlocklist is IVaultAdmin {
  /**
   * @notice Event emitted on blocklist update
   * @param caller The address of the function caller
   * @param account The address of the account updated
   * @param blocked Whether account is blocked or not
   */
  event BlocklistUpdated(address indexed caller, address indexed account, bool blocked);

  /**
   * @notice Event emitted when blocklist manager address is updated
   * @param caller The address of the function caller
   * @param blocklistManager The address of the new blocklist manager
   */
  event BlocklistManagerUpdated(address indexed caller, address indexed blocklistManager);

  /**
   * @notice blocklist manager address
   * @return The address of the blocklist manager
   */
  function blocklistManager() external view returns (address);

  /**
   * @notice Checks whether account is blocked or not
   * @param account The account to check
   * @return `true` for the blocked account, `false` otherwise
   */
  function blockedAccounts(address account) external view returns (bool);

  /**
   * @notice Add or remove account from the blocklist. Can only be called by the blocklist manager.
   * @param account The account to add or remove to the blocklist
   * @param blocked Whether account should be blocked or not
   */
  function updateBlocklist(address account, bool blocked) external;

  /**
   * @notice Used to update the blocklist manager. Can only be called by the Vault admin.
   * @param _blocklistManager The address of the new blocklist manager
   */
  function setBlocklistManager(address _blocklistManager) external;
}
