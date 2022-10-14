// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

/**
 * @title IVaultVersion
 * @author StakeWise
 * @notice Defines the interface for the Vault version
 */
interface IVaultVersion {
  /**
   * @notice Vault Version
   * @return The version of the Vault's implementation contract
   */
  function version() external view returns (uint8);

  /**
   * @notice Vault Implementation
   * @return The address of the Vault's implementation contract
   */
  function implementation() external view returns (address);
}
