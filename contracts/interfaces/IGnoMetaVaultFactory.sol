// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

/**
 * @title IGnoMetaVaultFactory
 * @author StakeWise
 * @notice Defines the interface for the GNO Meta Vault Factory contract
 */
interface IGnoMetaVaultFactory {
    /**
     * @notice Event emitted on a MetaVault creation
     * @dev the caller address is redundant, but keep it in the event for backward compatibility
     * @param caller The address of the factory caller
     * @param admin The address of the Vault admin
     * @param vault The address of the created Vault
     * @param params The encoded parameters for initializing the Vault contract
     */
    event MetaVaultCreated(address indexed caller, address indexed admin, address indexed vault, bytes params);

    /**
     * @notice The address of the Vault implementation contract used for proxy creation
     * @return The address of the Vault implementation contract
     */
    function implementation() external view returns (address);

    /**
     * @notice The address of the Vault admin used for Vault creation
     * @return The address of the Vault admin
     */
    function vaultAdmin() external view returns (address);

    /**
     * @notice Create Vault. Must transfer security deposit together with a call.
     * @param params The encoded parameters for initializing the Vault contract
     */
    function createVault(bytes calldata params) external returns (address vault);
}
