// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IEthVault} from "./IEthVault.sol";

/**
 * @title IEthCommunityVault
 * @author StakeWise
 * @notice Defines the interface for the EthCommunityVault contract
 */
interface IEthCommunityVault is IEthVault {
    /**
     * @dev Struct for initializing the EthCommunityVault contract
     * @param admin The address of the Vault admin
     * @param nodesManager The address of the nodes manager (fee recipient and validators manager)
     * @param capacity The Vault stops accepting deposits after exceeding the capacity
     * @param feePercent The fee percent that is charged by the Vault
     * @param metadataIpfsHash The IPFS hash of the Vault's metadata file
     */
    struct EthCommunityVaultInitParams {
        address admin;
        address nodesManager;
        uint256 capacity;
        uint16 feePercent;
        string metadataIpfsHash;
    }
}
