// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

/**
 * @title ISubVaultsRegistryFactory
 * @author StakeWise
 * @notice Defines the interface for the SubVaultsRegistry Factory contract
 */
interface ISubVaultsRegistryFactory {
    /**
     * @notice Emitted when a new SubVaultsRegistry is created
     * @param metaVault The address of the meta vault that created the registry
     * @param subVaultsRegistry The address of the created SubVaultsRegistry
     */
    event SubVaultsRegistryCreated(address indexed metaVault, address indexed subVaultsRegistry);

    /**
     * @notice The address of the SubVaultsRegistry implementation contract used for proxy creation
     * @return The address of the SubVaultsRegistry implementation contract
     */
    function implementation() external view returns (address);

    /**
     * @notice Creates a new SubVaultsRegistry contract
     * @return The address of the created SubVaultsRegistry contract
     */
    function createSubVaultsRegistry() external returns (address);
}
