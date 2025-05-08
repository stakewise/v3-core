// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

/**
 * @title IEthMetaVaultFactory
 * @author StakeWise
 * @notice Defines the interface for the ETH Meta Vault Factory contract
 */
interface IEthMetaVaultFactory {
    /**
     * @notice Event emitted on a MetaVault creation
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
     * @param admin The address of the Vault admin
     * @param params The encoded parameters for initializing the Vault contract
     */
    function createVault(address admin, bytes calldata params) external payable returns (address vault);
}
