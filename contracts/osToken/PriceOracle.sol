// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {IChainlinkAggregator} from '../interfaces/IChainlinkAggregator.sol';
import {IOsToken} from '../interfaces/IOsToken.sol';

/**
 * @title PriceOracle
 * @author StakeWise
 * @notice Price feed for osToken (e.g osETH price in ETH)
 */
contract PriceOracle is IChainlinkAggregator {
  address public immutable osToken;

  /**
   * @dev Constructor
   * @param _osToken The address of the osToken
   */
  constructor(address _osToken) {
    osToken = _osToken;
  }

  /**
   * @notice Returns the price of a unit of osToken (e.g price of osETH in ETH)
   * @return The price of a unit of osToken (with 18 decimals)
   */
  function latestAnswer() external view override returns (int256) {
    uint256 value = IOsToken(osToken).convertToAssets(10 ** decimals());
    // cannot realistically overflow, but better to check
    return (value > uint256(type(int256).max)) ? type(int256).max : int256(value);
  }

  /**
   * @notice Returns the number of decimals the price is formatted with
   * @return The number of decimals
   */
  function decimals() public pure returns (uint8) {
    return 18;
  }
}
