// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IKeeperRewards} from "./IKeeperRewards.sol";
import {IVaultFee} from "./IVaultFee.sol";

/**
 * @title IVaultState
 * @author StakeWise
 * @notice Defines the interface for the VaultState contract
 */
interface IVaultState is IVaultFee {
    /**
     * @notice Event emitted on checkpoint creation
     * @param shares The number of burned shares
     * @param assets The amount of exited assets
     */
    event CheckpointCreated(uint256 shares, uint256 assets);

    /**
     * @notice Event emitted on minting fee recipient shares
     * @param receiver The address of the fee recipient
     * @param shares The number of minted shares
     * @param assets The amount of minted assets
     */
    event FeeSharesMinted(address receiver, uint256 shares, uint256 assets);

    /**
     * @notice Event emitted when exiting assets are penalized (deprecated)
     * @param penalty The total penalty amount
     */
    event ExitingAssetsPenalized(uint256 penalty);

    /**
     * @notice Event emitted when the assets are donated to the Vault
     * @param sender The address of the sender
     * @param assets The amount of donated assets
     */
    event AssetsDonated(address sender, uint256 assets);

    /**
     * @notice Total assets in the Vault
     * @return The total amount of the underlying asset that is "managed" by Vault
     */
    function totalAssets() external view returns (uint256);

    /**
     * @notice Function for retrieving total shares
     * @return The amount of shares in existence
     */
    function totalShares() external view returns (uint256);

    /**
     * @notice The Vault's capacity
     * @return The amount after which the Vault stops accepting deposits
     */
    function capacity() external view returns (uint256);

    /**
     * @notice Total assets available in the Vault. They can be staked or withdrawn.
     * @return The total amount of withdrawable assets
     */
    function withdrawableAssets() external view returns (uint256);

    /**
     * @notice Get exit queue data
     * @return queuedShares The number of shares in the exit queue
     * @return unclaimedAssets The amount of unclaimed assets in the exit queue
     * @return totalExitingTickets The total number of exiting tickets
     * @return totalExitingAssets The total amount of exiting assets
     * @return totalTickets The total number of tickets in the exit queue
     */
    function getExitQueueData()
        external
        view
        returns (
            uint128 queuedShares,
            uint128 unclaimedAssets,
            uint128 totalExitingTickets,
            uint128 totalExitingAssets,
            uint256 totalTickets
        );

    /**
     * @notice Returns the number of shares held by an account
     * @param account The account for which to look up the number of shares it has, i.e. its balance
     * @return The number of shares held by the account
     */
    function getShares(address account) external view returns (uint256);

    /**
     * @notice Converts assets to shares
     * @param assets The amount of assets to convert to shares
     * @return shares The amount of shares that the Vault would exchange for the amount of assets provided
     */
    function convertToShares(uint256 assets) external view returns (uint256 shares);

    /**
     * @notice Converts shares to assets
     * @param shares The amount of shares to convert to assets
     * @return assets The amount of assets that the Vault would exchange for the amount of shares provided
     */
    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    /**
     * @notice Check whether state update is required
     * @return `true` if state update is required, `false` otherwise
     */
    function isStateUpdateRequired() external view returns (bool);

    /**
     * @notice Updates the total amount of assets in the Vault and its exit queue
     * @param harvestParams The parameters for harvesting Keeper rewards
     */
    function updateState(IKeeperRewards.HarvestParams calldata harvestParams) external;
}
