// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.16;

/**
 * @title IVaultFactory
 * @author StakeWise
 * @notice Defines the interface for the Vault Factory contract
 */
interface IVaultFactory {
  /**
   * @notice Event emitted on a Vault creation
   * @param caller The address that called the create function
   * @param vaultId The ID assigned to the Vault
   * @param vault The address of the created Vault
   **/
  event VaultCreated(address indexed caller, uint256 indexed vaultId, address vault);

  /**
   * @notice Create new Vault
   * @return vaultId The ID of the new Vault
   * @return vault The address of the new Vault
   */
  function createVault() external returns (uint256 vaultId, address vault);

  /**
   * @notice Retrieve Vault address
   * @param vaultId The Vault ID assigned during the deployment
   * @return The address of the Vault
   */
  function getVaultAddress(uint256 vaultId) external view returns (address);
}
