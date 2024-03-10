// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

/**
 * @title IXdaiExchange
 * @author StakeWise
 * @notice Defines the interface for the xDAI exchange contract
 */
interface IXdaiExchange {
  /**
   * @notice Initializes the xDAI exchange contract. Can only be called once.
   * @param initialOwner The address of the initial owner
   */
  function initialize(address initialOwner) external;

  /**
   * @notice Swaps xDAI to GNO. The amount of xDAI to swap is determined by the value of msg.value.
   *         Can only be called by the xDAI manager.
   * @param limit The minimum amount of GNO to receive
   * @param deadline The deadline for the swap
   * @return assets The amount of GNO received
   */
  function swap(uint256 limit, uint256 deadline) external payable returns (uint256 assets);
}
