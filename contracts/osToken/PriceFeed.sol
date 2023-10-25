// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {IChainlinkAggregator} from '../interfaces/IChainlinkAggregator.sol';
import {IChainlinkV3Aggregator} from '../interfaces/IChainlinkV3Aggregator.sol';
import {IBalancerRateProvider} from '../interfaces/IBalancerRateProvider.sol';
import {IOsTokenVaultController} from '../interfaces/IOsTokenVaultController.sol';

/**
 * @title PriceFeed
 * @author StakeWise
 * @notice Price feed for osToken (e.g osETH price in ETH)
 */
contract PriceFeed is IBalancerRateProvider, IChainlinkAggregator, IChainlinkV3Aggregator {
  error NotImplemented();

  /// @inheritdoc IChainlinkV3Aggregator
  uint256 public constant override version = 0;

  address public immutable osTokenVaultController;

  /// @inheritdoc IChainlinkV3Aggregator
  string public override description;

  /**
   * @dev Constructor
   * @param _osTokenVaultController The address of the OsTokenVaultController contract
   * @param _description The description of the price feed
   */
  constructor(address _osTokenVaultController, string memory _description) {
    osTokenVaultController = _osTokenVaultController;
    description = _description;
  }

  /// @inheritdoc IBalancerRateProvider
  function getRate() public view override returns (uint256) {
    return IOsTokenVaultController(osTokenVaultController).convertToAssets(10 ** decimals());
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
