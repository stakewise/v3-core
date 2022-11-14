// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

/**
 * @title IVersioned
 * @author StakeWise
 * @notice Defines the interface for the Versioned contract
 */
interface IVersioned {
  /// Custom errors
  error NotImplementedError();

  /**
   * @notice Version
   * @return The version of the proxy contract
   */
  function version() external view returns (uint8);

  /**
   * @notice Implementation
   * @return The address of the implementation contract
   */
  function implementation() external view returns (address);
}
