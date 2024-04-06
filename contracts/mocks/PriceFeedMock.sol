// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
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

  int256 private _latestAnswer;
  uint256 private _latestTimestamp;

  /**
   * @dev Constructor
   * @param _description The description of the price feed
   */
  constructor(string memory _description) Ownable(msg.sender) {
    description = _description;
  }

  /// @inheritdoc IBalancerRateProvider
  function getRate() public view override returns (uint256) {
    return SafeCast.toUint256(latestAnswer());
  }

  function setLatestAnswer(int256 latestAnswer_) external onlyOwner {
    _latestAnswer = latestAnswer_;
  }

  function setLatestTimestamp(uint256 latestTimestamp_) external onlyOwner {
    _latestTimestamp = latestTimestamp_;
  }

  /// @inheritdoc IChainlinkAggregator
  function latestAnswer() public view override returns (int256) {
    return _latestAnswer;
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
    return (0, latestAnswer(), _latestTimestamp, _latestTimestamp, 0);
  }
}
