// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity =0.8.22;

/**
 * @title Multicall
 * @author Uniswap
 * @notice Adopted from https://github.com/Uniswap/v3-periphery/blob/1d69caf0d6c8cfeae9acd1f34ead30018d6e6400/contracts/base/Multicall.sol
 * @notice Enables calling multiple methods in a single call to the contract
 */
interface IMulticall {
  /**
   * @notice Call multiple functions in the current contract and return the data from all of them if they all succeed
   * @param data The encoded function data for each of the calls to make to this contract
   * @return results The results from each of the calls passed in via data
   */
  function multicall(bytes[] calldata data) external returns (bytes[] memory results);
}
