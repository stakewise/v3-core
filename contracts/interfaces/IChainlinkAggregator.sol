// SPDX-License-Identifier: MIT

pragma solidity =0.8.20;

/**
 * @title IChainlinkAggregator
 * @author Chainlink
 * @dev Copied from https://github.com/smartcontractkit/chainlink/blob/master/contracts/src/v0.8/interfaces/AggregatorInterface.sol
 * @notice Interface for Chainlink aggregator contract
 */
interface IChainlinkAggregator {
  /**
   * @notice Returns the price of a unit of osToken (e.g price of osETH in ETH)
   * @return The price of a unit of osToken (with 18 decimals)
   */
  function latestAnswer() external view returns (int256);

  /**
   * @notice The last updated at block timestamp
   * @return The timestamp of the last update
   */
  function latestTimestamp() external view returns (uint256);
}
