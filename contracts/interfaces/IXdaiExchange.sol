// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

/**
 * @title IXdaiExchange
 * @author StakeWise
 * @notice Defines the interface for the xDAI exchange contract
 */
interface IXdaiExchange {
  /**
   * @notice Emitted when the maximum slippage is changed
   * @param maxSlippage The new maximum slippage
   */
  event MaxSlippageUpdated(uint16 maxSlippage);

  /**
   * @notice Returns the maximum slippage for the exchange
   * @return The maximum slippage in bps (1/10,000)
   */
  function maxSlippage() external view returns (uint16);

  /**
   * @notice Initializes the xDAI exchange contract. Can only be called once.
   * @param initialOwner The address of the initial owner
   * @param _maxSlippage The maximum slippage for the exchange in bps (1/10,000)
   */
  function initialize(address initialOwner, uint16 _maxSlippage) external;

  /**
   * @notice Sets the maximum slippage for the exchange. Can only be called by the owner.
   * @param newMaxSlippage The new maximum slippage
   */
  function setMaxSlippage(uint16 newMaxSlippage) external;

  /**
   * @notice Swaps xDAI to GNO. The amount of xDAI to swap is determined by the value of msg.value.
   * @return assets The amount of GNO received
   */
  function swap() external payable returns (uint256 assets);
}
