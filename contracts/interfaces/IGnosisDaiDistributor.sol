// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

/**
 * @title IGnosisDaiDistributor
 * @author StakeWise
 * @notice Defines the interface for the GnosisDaiDistributor
 */
interface IGnosisDaiDistributor {
  /**
   * @notice Event emitted when sDAI is distributed to the users
   * @param vault The address of the vault
   * @param amount The amount of sDAI distributed
   */
  event DaiDistributed(address indexed vault, uint256 amount);

  /**
   * @notice Distribute sDAI to the users. Can be called only by the vaults. Must transfer xDAI together with the call.
   */
  function distributeDai() external payable;
}
