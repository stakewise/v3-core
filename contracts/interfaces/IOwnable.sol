// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

/**
 * @title IOwnable
 * @author StakeWise
 * @notice Defines the interface for the Ownable contract
 */
interface IOwnable {
  /**
   * @notice Returns the address of the owner of the contract.
   * @return The address of the owner
   */
  function owner() external view returns (address);
}
