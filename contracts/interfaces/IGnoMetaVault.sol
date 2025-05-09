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

/**
 * @title IGnoMetaVault
 * @author StakeWise
 * @notice Defines the interface for the GnoMetaVault contract
 */
interface IGnoMetaVault is
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
     * @dev Struct for deploying the GnoMetaVault contract
     * @param keeper The address of the Keeper contract
     * @param vaultsRegistry The address of the VaultsRegistry contract
     * @param osTokenVaultController The address of the OsTokenVaultController contract
     * @param osTokenConfig The address of the OsTokenConfig contract
     * @param osTokenVaultEscrow The address of the OsTokenVaultEscrow contract
     * @param curatorsRegistry The address of the CuratorsRegistry contract
     * @param gnoToken The address of the GNO token
     * @param exitingAssetsClaimDelay The delay after which the assets can be claimed after exiting from staking
     */
    struct GnoMetaVaultConstructorArgs {
        address keeper;
        address vaultsRegistry;
        address osTokenVaultController;
        address osTokenConfig;
        address osTokenVaultEscrow;
        address curatorsRegistry;
        address gnoToken;
        uint64 exitingAssetsClaimDelay;
    }

    /**
     * @dev Struct for initializing the GnoMetaVault contract
     * @param subVaultsCurator The address of the initial sub-vaults curator
     * @param capacity The Vault stops accepting deposits after exceeding the capacity
     * @param feePercent The fee percent that is charged by the Vault
     * @param metadataIpfsHash The IPFS hash of the Vault's metadata file
     */
    struct GnoMetaVaultInitParams {
        address subVaultsCurator;
        uint256 capacity;
        uint16 feePercent;
        string metadataIpfsHash;
    }

    /**
     * @notice Initializes or upgrades the GnoMetaVault contract. Must transfer security deposit during the deployment.
     * @param params The encoded parameters for initializing the GnoVault contract
     */
    function initialize(bytes calldata params) external payable;

    /**
     * @notice Deposit GNO to the Vault
     * @param assets The amount of GNO to deposit
     * @param receiver The address that will receive Vault's shares
     * @param referrer The address of the referrer. Set to zero address if not used.
     * @return shares The number of shares minted
     */
    function deposit(uint256 assets, address receiver, address referrer) external returns (uint256 shares);

    /**
     * @notice Donate assets to the Vault. Must approve GNO transfer before the call.
     * @param amount The amount of GNO to donate
     */
    function donateAssets(uint256 amount) external;
}
