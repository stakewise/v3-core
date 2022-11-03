// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

/**
 * @title IRegistry
 * @author StakeWise
 * @notice Defines the interface for the Registry
 */
interface IRegistry {
  /// Custom errors
  error AccessDenied();
  error AlreadyAdded();
  error AlreadyRemoved();
  error InvalidUpgrade();

  /**
   * @notice Event emitted on a Vault addition
   * @param factory The address of the factory that has added the Vault
   * @param vault The address of the added Vault
   * @param timestamp The Vault addition timestamp
   */
  event VaultAdded(address indexed factory, address indexed vault, uint256 timestamp);

  /**
   * @notice Event emitted on added upgrades
   * @param fromImpl The address of the implementation contract before the upgrade
   * @param toImpl The address of the implementation contract after the upgrade
   */
  event UpgradeAdded(address indexed fromImpl, address indexed toImpl);

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
   * @notice Registered Factories
   * @param factory The address of the factory to check whether it is whitelisted
   * @return `true` for the whitelisted Factory, `false` otherwise
   */
  function factories(address factory) external view returns (bool);

  /**
   * @notice Upgrades
   * @param fromImpl The address of the implementation contract to upgrade from
   * @return toImpl The address of the implementation contract to upgrade to
   */
  function upgrades(address fromImpl) external view returns (address toImpl);

  /**
   * @notice Function for adding Vault to the registry. Can only be called by the whitelisted Factory.
   * @param vault The address of the Vault to add
   */
  function addVault(address vault) external;

  /**
   * @notice Function for adding upgrade from one implementation contract to another
   * @param prevImpl The address of the implementation contract to upgrade from
   * @param newImpl The address of the implementation contract to upgrade to
   */
  function addUpgrade(address prevImpl, address newImpl) external;

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
}
