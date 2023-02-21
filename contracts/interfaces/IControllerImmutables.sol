// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.18;

/**
 * @title IControllerImmutables
 * @author StakeWise
 * @notice Defines the interface for the ControllerImmutables contract
 */
interface IControllerImmutables {
  /**
   * @notice The Keeper address
   * @return The address of the Keeper contract
   */
  function keeper() external view returns (address);

  /**
   * @notice The Vaults Registry address
   * @return The address of the Vaults' registry contract
   */
  function vaultsRegistry() external view returns (address);

  /**
   * @notice The OsToken address
   * @return The address of the OsToken contract
   */
  function osToken() external view returns (address);
}
