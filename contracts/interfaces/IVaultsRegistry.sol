// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

/**
 * @title IVaultsRegistry
 * @author StakeWise
 * @notice Defines the interface for the VaultsRegistry
 */
interface IVaultsRegistry {
  /**
   * @notice Event emitted on a Vault addition
   * @param caller The address that has added the Vault
   * @param vault The address of the added Vault
   */
  event VaultAdded(address indexed caller, address indexed vault);

  /**
   * @notice Event emitted on adding Vault implementation contract
   * @param impl The address of the new implementation contract
   */
  event VaultImplAdded(address indexed impl);

  /**
   * @notice Event emitted on removing Vault implementation contract
   * @param impl The address of the removed implementation contract
   */
  event VaultImplRemoved(address indexed impl);

  /**
   * @notice Event emitted on whitelisting the factory
   * @param factory The address of the whitelisted factory
   */
  event FactoryAdded(address indexed factory);

  /**
   * @notice Event emitted on removing the factory from the whitelist
   * @param factory The address of the factory removed from the whitelist
   */
  event FactoryRemoved(address indexed factory);

  /**
   * @notice Registered Vaults
   * @param vault The address of the vault to check whether it is registered
   * @return `true` for the registered Vault, `false` otherwise
   */
  function vaults(address vault) external view returns (bool);

  /**
   * @notice Registered Vault implementations
   * @param impl The address of the vault implementation
   * @return `true` for the registered implementation, `false` otherwise
   */
  function vaultImpls(address impl) external view returns (bool);

  /**
   * @notice Registered Factories
   * @param factory The address of the factory to check whether it is whitelisted
   * @return `true` for the whitelisted Factory, `false` otherwise
   */
  function factories(address factory) external view returns (bool);

  /**
   * @notice Function for adding Vault to the registry. Can only be called by the whitelisted Factory.
   * @param vault The address of the Vault to add
   */
  function addVault(address vault) external;

  /**
   * @notice Function for adding Vault implementation contract
   * @param newImpl The address of the new implementation contract
   */
  function addVaultImpl(address newImpl) external;

  /**
   * @notice Function for removing Vault implementation contract
   * @param impl The address of the removed implementation contract
   */
  function removeVaultImpl(address impl) external;

  /**
   * @notice Function for adding the factory to the whitelist
   * @param factory The address of the factory to add to the whitelist
   */
  function addFactory(address factory) external;

  /**
   * @notice Function for removing the factory from the whitelist
   * @param factory The address of the factory to remove from the whitelist
   */
  function removeFactory(address factory) external;

  /**
   * @notice Function for initializing the registry. Can only be called once during the deployment.
   * @param _owner The address of the owner of the contract
   */
  function initialize(address _owner) external;
}
