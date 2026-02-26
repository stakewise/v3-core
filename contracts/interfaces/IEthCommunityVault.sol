// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IEthErc20Vault} from "./IEthErc20Vault.sol";

/**
 * @title IEthCommunityVault
 * @author StakeWise
 * @notice Defines the interface for the EthCommunityVault contract
 */
interface IEthCommunityVault is IEthErc20Vault {
    /**
     * @notice Event emitted on EthCommunityVault creation
     * @param admin The address of the Vault admin
     * @param nodesManager The address of the nodes manager
     * @param capacity The capacity of the Vault
     * @param feePercent The fee percent of the Vault
     * @param name The name of the ERC20 token
     * @param symbol The symbol of the ERC20 token
     * @param metadataIpfsHash The IPFS hash of the Vault metadata
     */
    event EthCommunityVaultCreated(
        address admin,
        address nodesManager,
        uint256 capacity,
        uint16 feePercent,
        string name,
        string symbol,
        string metadataIpfsHash
    );

    /**
     * @dev Struct for initializing the EthCommunityVault contract
     * @param admin The address of the Vault admin
     * @param nodesManager The address of the nodes manager (fee recipient and validators manager)
     * @param capacity The Vault stops accepting deposits after exceeding the capacity
     * @param feePercent The fee percent that is charged by the Vault
     * @param name The name of the ERC20 token
     * @param symbol The symbol of the ERC20 token
     * @param metadataIpfsHash The IPFS hash of the Vault's metadata file
     */
    struct EthCommunityVaultInitParams {
        address admin;
        address nodesManager;
        uint256 capacity;
        uint16 feePercent;
        string name;
        string symbol;
        string metadataIpfsHash;
    }
}
