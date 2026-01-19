// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IVaultAdmin} from "./IVaultAdmin.sol";
import {IVaultVersion} from "./IVaultVersion.sol";
import {IVaultFee} from "./IVaultFee.sol";
import {IVaultState} from "./IVaultState.sol";
import {IVaultEnterExit} from "./IVaultEnterExit.sol";
import {IVaultOsToken} from "./IVaultOsToken.sol";
import {IVaultSubVaults} from "./IVaultSubVaults.sol";
import {IMulticall} from "./IMulticall.sol";
import {ISubVaultsCurator} from "./ISubVaultsCurator.sol";

/**
 * @title IMetaVault
 * @author StakeWise
 * @notice Defines the interface for the MetaVault contract
 */
interface IMetaVault is
    IVaultAdmin,
    IVaultVersion,
    IVaultFee,
    IVaultState,
    IVaultEnterExit,
    IVaultOsToken,
    IVaultSubVaults,
    IMulticall
{
    /**
     * @notice Event emitted when assets are redeemed from sub-vaults
     * @param assetsRedeemed The amount of assets redeemed to the meta vault
     */
    event SubVaultsAssetsRedeemed(uint256 assetsRedeemed);

    /**
     * @dev Struct for deploying the MetaVault contract
     * @param keeper The address of the Keeper contract
     * @param vaultsRegistry The address of the VaultsRegistry contract
     * @param osTokenVaultController The address of the OsTokenVaultController contract
     * @param osTokenConfig The address of the OsTokenConfig contract
     * @param osTokenVaultEscrow The address of the OsTokenVaultEscrow contract
     * @param curatorsRegistry The address of the CuratorsRegistry contract
     * @param exitingAssetsClaimDelay The delay after which the assets can be claimed after exiting from staking
     */
    struct MetaVaultConstructorArgs {
        address keeper;
        address vaultsRegistry;
        address osTokenVaultController;
        address osTokenConfig;
        address osTokenVaultEscrow;
        address curatorsRegistry;
        uint64 exitingAssetsClaimDelay;
    }

    /**
     * @dev Struct for initializing the MetaVault contract
     * @param subVaultsCurator The address of the initial sub-vaults curator
     * @param capacity The Vault stops accepting deposits after exceeding the capacity
     * @param feePercent The fee percent that is charged by the Vault
     * @param metadataIpfsHash The IPFS hash of the Vault's metadata file
     */
    struct MetaVaultInitParams {
        address subVaultsCurator;
        uint256 capacity;
        uint16 feePercent;
        string metadataIpfsHash;
    }

    /**
     * @notice Calculates the required sub-vaults exit requests to fulfill the assets to redeem
     * @param assetsToRedeem The amount of assets to redeem
     * @return redeemRequests The array of sub-vaults exit requests
     */
    function calculateSubVaultsRedemptions(uint256 assetsToRedeem)
        external
        view
        returns (ISubVaultsCurator.ExitRequest[] memory redeemRequests);

    /**
     * @notice Redeems assets from sub-vaults to the meta vault. Can only be called by the redeemer.
     * @param assetsToRedeem The amount of assets to redeem to the meta vault
     * @return totalRedeemedAssets The total amount of assets redeemed from sub-vaults
     */
    function redeemSubVaultsAssets(uint256 assetsToRedeem) external returns (uint256 totalRedeemedAssets);
}
