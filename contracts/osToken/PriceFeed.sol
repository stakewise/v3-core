// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {IChainlinkAggregator} from '../interfaces/IChainlinkAggregator.sol';
import {IChainlinkV3Aggregator} from '../interfaces/IChainlinkV3Aggregator.sol';
import {IOsToken} from '../interfaces/IOsToken.sol';

/**
 * @title PriceFeed
 * @author StakeWise
 * @notice Price feed for osToken (e.g osETH price in ETH)
 */
contract PriceFeed is IChainlinkAggregator, IChainlinkV3Aggregator {
  error NotImplemented();

  /// @inheritdoc IChainlinkV3Aggregator
  uint256 public constant override version = 0;

  address public immutable osToken;

  /// @inheritdoc IChainlinkV3Aggregator
  string public override description;

  /**
   * @dev Constructor
   * @param _osToken The address of the osToken
   * @param _description The description of the price feed
   */
  constructor(address _osToken, string memory _description) {
    osToken = _osToken;
    description = _description;
  }

  /// @inheritdoc IChainlinkAggregator
  function latestAnswer() public view override returns (int256) {
    uint256 value = IOsToken(osToken).convertToAssets(10 ** decimals());
    // cannot realistically overflow, but better to check
    return (value > uint256(type(int256).max)) ? type(int256).max : int256(value);
  }

  /// @inheritdoc IChainlinkAggregator
  function latestTimestamp() external view returns (uint256) {
    return block.timestamp;
  }

  /// @inheritdoc IChainlinkV3Aggregator
  function decimals() public pure returns (uint8) {
    return 18;
  }

  /// @inheritdoc IChainlinkV3Aggregator
  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    )
  {
    return (uint80(0), latestAnswer(), block.timestamp, block.timestamp, uint80(0));
  }
}
