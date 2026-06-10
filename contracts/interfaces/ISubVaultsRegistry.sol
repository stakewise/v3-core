// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IMulticall} from "./IMulticall.sol";
import {ISubVaultsCurator} from "./ISubVaultsCurator.sol";

/**
 * @title ISubVaultsRegistry
 * @author StakeWise
 * @notice Defines the interface for the SubVaultsRegistry contract
 */
interface ISubVaultsRegistry is IMulticall {
    /**
     * @notice Struct for sub vault exit request
     * @param exitQueueIndex The index of the exit queue
     * @param vault The address of the sub vault
     * @param timestamp The timestamp of the exit request
     */
    struct SubVaultExitRequest {
        uint256 exitQueueIndex;
        address vault;
        uint64 timestamp;
    }

    /**
     * @notice Struct for sub vault state
     * @param stakedShares The number of shares staked in the sub vault
     * @param queuedShares The number of shares queued for exit in the sub vault
     */
    struct SubVaultState {
        uint128 stakedShares;
        uint128 queuedShares;
    }

    /**
     * @notice Emitted when the sub vaults are harvested
     * @param totalAssetsDelta The change in total assets after the harvest
     */
    event SubVaultsHarvested(int256 totalAssetsDelta);

    /**
     * @notice Emitted when the sub-vaults curator is updated
     * @param curator The address of the new sub-vaults curator
     */
    event SubVaultsCuratorUpdated(address indexed curator);

    /**
     * @notice Emitted when the rewards nonce is updated
     * @param rewardsNonce The new rewards nonce
     */
    event RewardsNonceUpdated(uint256 rewardsNonce);

    /**
     * @notice Emitted when a new sub-vault is added
     * @param vault The address of the sub-vault
     */
    event SubVaultAdded(address indexed vault);

    /**
     * @notice Emitted when a new meta sub-vault is proposed
     * @param vault The address of the meta sub-vault
     */
    event MetaSubVaultProposed(address indexed vault);

    /**
     * @notice Emitted when a meta sub-vault is rejected
     * @param vault The address of the meta sub-vault
     */
    event MetaSubVaultRejected(address indexed vault);

    /**
     * @notice Emitted when a sub-vault is ejecting
     * @param vault The address of the sub-vault
     */
    event SubVaultEjecting(address indexed vault);

    /**
     * @notice Emitted when a sub-vault is ejected
     * @param vault The address of the sub-vault
     */
    event SubVaultEjected(address indexed vault);

    /**
     * @notice Event emitted when assets are redeemed from sub-vaults
     * @param assetsRedeemed The amount of assets redeemed to the meta vault
     */
    event SubVaultsAssetsRedeemed(uint256 assetsRedeemed);

    /**
     * @notice Event emitted when state is migrated from meta vault
     * @param metaVault The address of the meta vault
     */
    event Migrated(address indexed metaVault);

    /**
     * @notice The address of the meta vault
     * @return The address of the meta vault
     */
    function metaVault() external view returns (address);

    /**
     * @notice The address of the sub-vaults curator
     * @return The address of the sub-vaults curator
     */
    function subVaultsCurator() external view returns (address);

    /**
     * @notice Pending meta sub-vault waiting for approval
     * @return The address of the pending meta sub-vault
     */
    function pendingMetaSubVault() external view returns (address);

    /**
     * @notice Function to get the rewards nonce of the sub-vaults
     * @return The rewards nonce
     */
    function subVaultsRewardsNonce() external view returns (uint128);

    /**
     * @notice The address of the sub-vault being ejected
     * @return The address of the ejecting sub-vault
     */
    function ejectingSubVault() external view returns (address);

    /**
     * @notice The number of shares of the ejecting sub-vault
     * @return The number of shares
     */
    function ejectingSubVaultShares() external view returns (uint256);

    /**
     * @notice Returns the state of a sub-vault
     * @param vault The address of the sub-vault
     * @return The state of the sub-vault
     */
    function subVaultsStates(address vault) external view returns (SubVaultState memory);

    /**
     * @notice Returns the exits queue for a sub-vault
     * @param vault The address of the sub-vault
     * @return The array of packed exit data (positionTicket: uint160, shares: uint96)
     */
    function subVaultsExits(address vault) external view returns (bytes32[] memory);

    /**
     * @notice Returns the list of sub-vaults
     * @return The array of sub-vault addresses
     */
    function getSubVaults() external view returns (address[] memory);

    /**
     * @notice Checks if the given address is a sub-vault
     * @param vault The address to check
     * @return True if the address is a sub-vault, false otherwise
     */
    function isSubVault(address vault) external view returns (bool);

    /**
     * @notice Initializes the SubVaultsRegistry
     * @param metaVault The address of the meta vault
     * @param curator The address of initial sub-vaults curator
     */
    function initialize(address metaVault, address curator) external;

    /**
     * @notice Function to update the sub-vaults curator. Can only be called by the meta vault admin.
     * @param curator The address of the new sub-vaults curator
     */
    function setSubVaultsCurator(address curator) external;

    /**
     * @notice Function to add a new sub-vault. Can only be called by the meta vault admin.
     * @param vault The address of the sub-vault to add
     */
    function addSubVault(address vault) external;

    /**
     * @notice Function to accept a meta sub-vault. Can only be called by the VaultsRegistry owner.
     * @param metaSubVault The address of the meta sub-vault to accept
     */
    function acceptMetaSubVault(address metaSubVault) external;

    /**
     * @notice Function to reject a meta sub-vault. Can only be called by the VaultsRegistry owner or meta vault admin.
     * @param metaSubVault The address of the meta sub-vault to reject
     */
    function rejectMetaSubVault(address metaSubVault) external;

    /**
     * @notice Function to eject a sub-vault. Can only be called by the meta vault admin.
     * All the sub-vault shares will be added to the exit queue.
     * @param vault The address of the sub-vault to eject
     */
    function ejectSubVault(address vault) external;

    /**
     * @notice Checks whether the state can be updated
     * @return True if the state can be updated, false otherwise
     */
    function canUpdateState() external view returns (bool);

    /**
     * @notice Checks whether the meta vault is collateralized
     * @return True if the meta vault is collateralized, false otherwise
     */
    function isCollateralized() external view returns (bool);

    /**
     * @notice The total assets deposited to sub-vaults
     */
    function subVaultsTotalAssets() external view returns (uint128);

    /**
     * @notice Checks whether the state update is required
     * @return True if the state update is required, false otherwise
     */
    function isStateUpdateRequired() external view returns (bool);

    /**
     * @notice Deposit available assets to the sub vaults
     */
    function depositToSubVaults() external;

    /**
     * @notice Claims exited assets from sub vaults
     * @param exitRequests The array of exit requests to claim
     */
    function claimSubVaultsExitedAssets(SubVaultExitRequest[] calldata exitRequests) external;

    /**
     * @notice Harvests sub-vaults assets. Can only be called by the meta vault.
     * @return totalAssetsDelta The change in total assets after the harvest
     * @return harvested Whether the sub-vaults were harvested
     */
    function harvestSubVaultsAssets() external returns (int256 totalAssetsDelta, bool harvested);

    /**
     * @notice Enters the exit queue for sub-vaults. Can only be called by the meta vault.
     */
    function enterSubVaultsExitQueue() external;

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
