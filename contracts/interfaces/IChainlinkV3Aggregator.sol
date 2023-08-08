// SPDX-License-Identifier: MIT

pragma solidity =0.8.20;

/**
 * @title IChainlinkAggregator
 * @author Chainlink
 * @dev Copied from https://github.com/smartcontractkit/chainlink/blob/master/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol
 * @notice Interface for Chainlink V3 aggregator contract
 */
interface IChainlinkV3Aggregator {
  /**
   * @notice The number of decimals the price is formatted with
   */
  function decimals() external view returns (uint8);

  /**
   * @notice The description of the aggregator
   */
  function description() external view returns (string memory);

  /**
   * @notice The version number of the aggregator
   */
  function version() external view returns (uint256);

  /**
   * @notice Get the data from the latest round
   * @return roundId The round ID
   * @return answer The current price
   * @return startedAt The timestamp of when the round started
   * @return updatedAt The timestamp of when the round was updated
   * @return answeredInRound (Deprecated) Previously used when answers could take multiple rounds to be computed
   */
  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );
}
