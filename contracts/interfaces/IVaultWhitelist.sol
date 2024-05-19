// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IVaultAdmin} from './IVaultAdmin.sol';

/**
 * @title IVaultWhitelist
 * @author StakeWise
 * @notice Defines the interface for the VaultWhitelist contract
 */
interface IVaultWhitelist is IVaultAdmin {
  /**
   * @notice Event emitted on whitelist update
   * @param caller The address of the function caller
   * @param account The address of the account updated
   * @param approved Whether account is approved or not
   */
  event WhitelistUpdated(address indexed caller, address indexed account, bool approved);

  /**
   * @notice Event emitted when whitelister address is updated
   * @param caller The address of the function caller
   * @param whitelister The address of the new whitelister
   */
  event WhitelisterUpdated(address indexed caller, address indexed whitelister);

  /**
   * @notice Whitelister address
   * @return The address of the whitelister
   */
  function whitelister() external view returns (address);

  /**
   * @notice Checks whether account is whitelisted or not
   * @param account The account to check
   * @return `true` for the whitelisted account, `false` otherwise
   */
  function whitelistedAccounts(address account) external view returns (bool);

  /**
   * @notice Add or remove account from the whitelist. Can only be called by the whitelister.
   * @param account The account to add or remove from the whitelist
   * @param approved Whether account should be whitelisted or not
   */
  function updateWhitelist(address account, bool approved) external;

  /**
   * @notice Used to update the whitelister. Can only be called by the Vault admin.
   * @param _whitelister The address of the new whitelister
   */
  function setWhitelister(address _whitelister) external;
}
