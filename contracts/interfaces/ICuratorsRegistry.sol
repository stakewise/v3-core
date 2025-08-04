// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

/**
 * @title ICuratorsRegistry
 * @author StakeWise
 * @notice Defines the interface for the CuratorsRegistry
 */
interface ICuratorsRegistry {
    /**
     * @notice Emitted when a new curator is added
     * @param sender The address of the sender
     * @param curator The address of the curator
     */
    event CuratorAdded(address indexed sender, address indexed curator);

    /**
     * @notice Emitted when a curator is removed
     * @param sender The address of the sender
     * @param curator The address of the curator
     */
    event CuratorRemoved(address indexed sender, address indexed curator);

    /**
     * @notice Checks if an address is a curator
     * @param curator The address of the curator
     * @return True if the address is a curator, false otherwise
     */
    function isCurator(address curator) external view returns (bool);

    /**
     * @notice Initializes the CuratorsRegistry
     * @param _owner The address of the owner
     */
    function initialize(address _owner) external;

    /**
     * @notice Adds a new curator
     * @param curator The address of the curator to add
     */
    function addCurator(address curator) external;

    /**
     * @notice Removes a curator
     * @param curator The address of the curator to remove
     */
    function removeCurator(address curator) external;
}
