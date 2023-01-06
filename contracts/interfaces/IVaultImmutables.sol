// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

/**
 * @title IVaultImmutables
 * @author StakeWise
 * @notice Defines the interface for the VaultImmutables contract
 */
interface IVaultImmutables {
  /**
   * @notice The Keeper address
   * @return The address of the Vault's keeper contract
   */
  function keeper() external view returns (address);

  /**
   * @notice The Registry address
   * @return The address of the Vault's registry contract
   */
  function registry() external view returns (address);

  /**
   * @notice Validators Registry
   * @return The address of the beacon chain validators registry contract
   */
  function validatorsRegistry() external view returns (address);
}
