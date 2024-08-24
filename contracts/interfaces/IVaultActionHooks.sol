// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

/**
 * @title IVaultActionHooks
 * @author StakeWise
 * @notice Defines the interface for the VaultActionHooks contract
 */
interface IVaultActionHooks {
  /**
   * @notice Executes the action on the user balance change
   * @param caller The address of the caller
   * @param user The address of the user
   * @param newBalance The new balance of the user
   */
  function onUserBalanceChange(address caller, address user, uint256 newBalance) external;
}
