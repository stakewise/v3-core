// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

interface IChainlinkAggregator {
  /**
   * @notice Reads the current answer from aggregator delegated to
   * @return The price of a unit
   */
  function latestAnswer() external view returns (int256);
}

interface IOsToken {
  /**
   * @notice Converts assets to shares
   * @param shares The amount of shares to convert to assets
   * @return assets The amount of assets that the OsToken would exchange for the amount of shares provided
   */
  function convertToAssets(uint256 shares) external view returns (uint256 assets);
}

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

    // check for overflow
    if (value > uint256(type(int256).max)) return 0;

    return int256(value);
  }

  /**
   * @notice Returns the number of decimals the price is formatted with
   * @return The number of decimals
   */
  function decimals() public pure returns (uint8) {
    return 18;
  }
}
