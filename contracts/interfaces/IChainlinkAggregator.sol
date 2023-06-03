// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

/**
 * @title IChainlinkAggregator
 * @author StakeWise
 * @notice Interface for Chainlink aggregator contract
 */
interface IChainlinkAggregator {
  /**
   * @notice Reads the current answer from aggregator delegated to
   * @return The price of a unit
   */
  function latestAnswer() external view returns (int256);
}
