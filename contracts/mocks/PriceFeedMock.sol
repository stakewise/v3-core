// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IChainlinkAggregator} from '../interfaces/IChainlinkAggregator.sol';
import {IChainlinkV3Aggregator} from '../interfaces/IChainlinkV3Aggregator.sol';
import {IBalancerRateProvider} from '../interfaces/IBalancerRateProvider.sol';

/**
 * @title PriceFeed
 * @author StakeWise
 * @notice Price feed mock
 */
contract PriceFeedMock is
  Ownable,
  IBalancerRateProvider,
  IChainlinkAggregator,
  IChainlinkV3Aggregator
{
  /// @inheritdoc IChainlinkV3Aggregator
  uint256 public constant override version = 0;

  /// @inheritdoc IChainlinkV3Aggregator
  string public override description;

  uint256 private _rate;

  /**
   * @dev Constructor
   * @param _description The description of the price feed
   */
  constructor(string memory _description) Ownable(msg.sender) {
    description = _description;
  }

  /// @inheritdoc IBalancerRateProvider
  function getRate() public view override returns (uint256) {
    return _rate;
  }

  function setRate(uint256 rate) external onlyOwner {
    _rate = rate;
  }

  /// @inheritdoc IChainlinkAggregator
  function latestAnswer() public view override returns (int256) {
    uint256 value = getRate();
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
    return (0, latestAnswer(), block.timestamp, block.timestamp, 0);
  }
}
