// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

/**
 * @title IVaultSubVaults
 * @author StakeWise
 * @notice Defines the interface for the VaultSubVaults contract
 */
interface IVaultSubVaults {
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
     * @notice Struct for submitting sub vault exit request
     * @param exitQueueIndex The index of the exit queue
     * @param vault The address of the vault
     * @param timestamp The timestamp of the exit request
     */
    struct SubVaultExitRequest {
        uint256 exitQueueIndex;
        address vault;
        uint64 timestamp;
    }

    /**
     * @notice Emitted when the rewards nonce is updated
     * @param rewardsNonce The new rewards nonce
     */
    event RewardsNonceUpdated(uint256 rewardsNonce);

    /**
     * @notice Emitted when the sub vaults are harvested
     * @param totalAssetsDelta The change in total assets after the harvest
     */
    event SubVaultsHarvested(int256 totalAssetsDelta);

    /**
     * @notice Emitted when the new sub-vault is added
     * @param caller The address of the caller
     * @param vault The address of the sub-vault
     */
    event SubVaultAdded(address indexed caller, address indexed vault);

    /**
     * @notice Emitted when the new meta sub-vault is proposed
     * @param caller The address of the caller
     * @param vault The address of the meta sub-vault
     */
    event MetaSubVaultProposed(address indexed caller, address indexed vault);

    /**
     * @notice Emitted when the meta sub-vault is rejected
     * @param caller The address of the caller
     * @param vault The address of the meta sub-vault
     */
    event MetaSubVaultRejected(address indexed caller, address indexed vault);

    /**
     * @notice Emitted when the sub-vault is ejecting
     * @param caller The address of the caller
     * @param vault The address of the sub-vault
     */
    event SubVaultEjecting(address indexed caller, address indexed vault);

    /**
     * @notice Emitted when the sub-vault is ejected
     * @param caller The address of the caller
     * @param vault The address of the sub-vault
     */
    event SubVaultEjected(address indexed caller, address indexed vault);

    /**
     * @notice Emitted when the sub-vaults curator is updated
     * @param caller The address of the caller
     * @param curator The address of the new sub-vaults curator
     */
    event SubVaultsCuratorUpdated(address indexed caller, address indexed curator);

    /**
     * @notice Sub-vaults curator contract
     * @return The address of the Sub-vaults curator contract
     */
    function subVaultsCurator() external view returns (address);

    /**
     * @notice Ejecting sub-vault
     * @return The address of the ejecting sub-vault
     */
    function ejectingSubVault() external view returns (address);

    /**
     * @notice Pending meta sub-vault waiting for approval
     * @return The address of the pending meta sub-vault
     */
    function pendingMetaSubVault() external view returns (address);

    /**
     * @notice Function to get the list sub-vaults
     * @return An array of addresses of the sub-vaults
     */
    function getSubVaults() external view returns (address[] memory);

    /**
     * @notice Function to get the rewards nonce of the sub-vaults
     * @return The rewards nonce
     */
    function subVaultsRewardsNonce() external view returns (uint128);

    /**
     * @notice Function to get the state of a sub-vault
     * @param vault The address of the sub-vault
     * @return The state of the sub-vault
     */
    function subVaultsStates(address vault) external view returns (SubVaultState memory);

    /**
     * @notice Checks whether the meta vault can be updated
     * @return `true` if the meta vault can be updated, `false` otherwise
     */
    function canUpdateState() external view returns (bool);

    /**
     * @notice Checks whether the vault is collateralized
     * @return `true` if the vault is collateralized, `false` otherwise
     */
    function isCollateralized() external view returns (bool);

    /**
     * @notice Function to update the the sub-vaults curator. Can only be called by the admin.
     * @param curator The address of the new sub-vaults curator
     */
    function setSubVaultsCurator(address curator) external;

    /**
     * @notice Function to add a new sub-vault. Can only be called by the admin.
     * @param vault The address of the sub-vault to add
     */
    function addSubVault(address vault) external;

    /**
     * @notice Function to accept a meta sub-vault. Can only be called by the VaultsRegistry owner.
     * @param metaSubVault The address of the meta sub-vault to accept
     */
    function acceptMetaSubVault(address metaSubVault) external;

    /**
     * @notice Function to reject a meta sub-vault. Can only be called by the VaultsRegistry owner or admin.
     * @param metaSubVault The address of the meta sub-vault to reject
     */
    function rejectMetaSubVault(address metaSubVault) external;

    /**
     * @notice Function to remove a sub-vault. Can only be called by the admin.
     * All the sub-vault shares will be added to the exit queue.
     * @param vault The address of the sub-vault to remove
     */
    function ejectSubVault(address vault) external;

    /**
     * @notice Deposit available assets to the sub vaults
     */
    function depositToSubVaults() external;

    /**
     * @notice Claim the exited assets from the sub vaults
     * @param exitRequests The array of exit requests to claim
     */
    function claimSubVaultsExitedAssets(SubVaultExitRequest[] calldata exitRequests) external;
}
