// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IKeeperRewards} from "./IKeeperRewards.sol";
import {IVaultAdmin} from "./IVaultAdmin.sol";
import {IVaultVersion} from "./IVaultVersion.sol";
import {IVaultFee} from "./IVaultFee.sol";
import {IVaultState} from "./IVaultState.sol";
import {IVaultEnterExit} from "./IVaultEnterExit.sol";
import {IVaultOsToken} from "./IVaultOsToken.sol";
import {IVaultSubVaults} from "./IVaultSubVaults.sol";
import {IMulticall} from "./IMulticall.sol";

/**
 * @title IEthMetaVault
 * @author StakeWise
 * @notice Defines the interface for the EthMetaVault contract
 */
interface IEthMetaVault is
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
     * @dev Struct for deploying the EthMetaVault contract
     * @param keeper The address of the Keeper contract
     * @param vaultsRegistry The address of the VaultsRegistry contract
     * @param osTokenVaultController The address of the OsTokenVaultController contract
     * @param osTokenConfig The address of the OsTokenConfig contract
     * @param osTokenVaultEscrow The address of the OsTokenVaultEscrow contract
     * @param subVaultsRegistry The address of the SubVaultsRegistry contract
     * @param exitingAssetsClaimDelay The delay after which the assets can be claimed after exiting from staking
     */
    struct EthMetaVaultConstructorArgs {
        address keeper;
        address vaultsRegistry;
        address osTokenVaultController;
        address osTokenConfig;
        address osTokenVaultEscrow;
        address subVaultsRegistry;
        uint64 exitingAssetsClaimDelay;
    }

    /**
     * @dev Struct for initializing the EthMetaVault contract
     * @param admin The address of the admin
     * @param capacity The Vault stops accepting deposits after exceeding the capacity
     * @param feePercent The fee percent that is charged by the Vault
     * @param metadataIpfsHash The IPFS hash of the Vault's metadata file
     */
    struct EthMetaVaultInitParams {
        address admin;
        uint256 capacity;
        uint16 feePercent;
        string metadataIpfsHash;
    }

    /**
     * @notice Initializes or upgrades the EthMetaVault contract. Must transfer security deposit during the deployment.
     * @param params The encoded parameters for initializing the EthVault contract
     */
    function initialize(bytes calldata params) external payable;

    /**
     * @notice Deposit ETH to the Vault
     * @param receiver The address that will receive Vault's shares
     * @param referrer The address of the referrer. Set to zero address if not used.
     * @return shares The number of shares minted
     */
    function deposit(address receiver, address referrer) external payable returns (uint256 shares);

    /**
     * @notice Updates Vault state and deposits ETH to the Vault
     * @param receiver The address that will receive Vault's shares
     * @param referrer The address of the referrer. Set to zero address if not used.
     * @param harvestParams The parameters for harvesting Keeper rewards
     * @return shares The number of shares minted
     */
    function updateStateAndDeposit(
        address receiver,
        address referrer,
        IKeeperRewards.HarvestParams calldata harvestParams
    ) external payable returns (uint256 shares);

    /**
     * @notice Deposits assets to the vault and mints OsToken shares to the receiver
     * @param receiver The address to receive the OsToken
     * @param osTokenShares The amount of OsToken shares to mint.
     *        If set to type(uint256).max, max OsToken shares will be minted.
     * @param referrer The address of the referrer
     * @return The amount of OsToken assets minted
     */
    function depositAndMintOsToken(address receiver, uint256 osTokenShares, address referrer)
        external
        payable
        returns (uint256);

    /**
     * @notice Updates the state, deposits assets to the vault and mints OsToken shares to the receiver
     * @param receiver The address to receive the OsToken
     * @param osTokenShares The amount of OsToken shares to mint.
     *        If set to type(uint256).max, max OsToken shares will be minted.
     * @param referrer The address of the referrer
     * @param harvestParams The parameters for the harvest
     * @return The amount of OsToken assets minted
     */
    function updateStateAndDepositAndMintOsToken(
        address receiver,
        uint256 osTokenShares,
        address referrer,
        IKeeperRewards.HarvestParams calldata harvestParams
    ) external payable returns (uint256);
}
