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
  event MaxSlippageUpdated(uint128 maxSlippage);

  /**
   * @notice Emitted when the stale price time delta is changed
   * @param stalePriceTimeDelta The new stale price time delta
   */
  event StalePriceTimeDeltaUpdated(uint128 stalePriceTimeDelta);

  /**
   * @notice Returns the maximum slippage for the exchange
   * @return The maximum slippage in bps (1/10,000)
   */
  function maxSlippage() external view returns (uint128);

  /**
   * @notice Returns the stale price time delta for the exchange
   * @return The stale price time delta in seconds
   */
  function stalePriceTimeDelta() external view returns (uint128);

  /**
   * @notice Initializes the xDAI exchange contract. Can only be called once.
   * @param initialOwner The address of the initial owner
   * @param _maxSlippage The maximum slippage for the exchange in bps (1/10,000)
   * @param _stalePriceTimeDelta The stale price time delta for the exchange in seconds
   */
  function initialize(
    address initialOwner,
    uint128 _maxSlippage,
    uint128 _stalePriceTimeDelta
  ) external;

  /**
   * @notice Sets the maximum slippage for the exchange. Can only be called by the owner.
   * @param newMaxSlippage The new maximum slippage
   */
  function setMaxSlippage(uint128 newMaxSlippage) external;

  /**
   * @notice Sets the stale price time delta for the exchange. Can only be called by the owner.
   * @param newStalePriceTimeDelta The new stale price time delta
   */
  function setStalePriceTimeDelta(uint128 newStalePriceTimeDelta) external;

  /**
   * @notice Swaps xDAI to GNO. The amount of xDAI to swap is determined by the value of msg.value.
   * @return assets The amount of GNO received
   */
  function swap() external payable returns (uint256 assets);
}
