// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IVaultState} from "./IVaultState.sol";

/**
 * @title IVaultSubVaults
 * @author StakeWise
 * @notice Defines the interface for the VaultSubVaults contract
 */
interface IVaultSubVaults is IVaultState {
    /**
     * @notice Returns the address of the SubVaultsRegistry contract
     * @return The address of the SubVaultsRegistry
     */
    function subVaultsRegistry() external view returns (address);

    /**
     * @notice Function to deposit assets to a sub vault. Can only be called by SubVaultsRegistry contract.
     * @param vault The address of the sub-vault
     * @param assets The amount of assets to deposit
     * @return shares The amount of vault shares received
     */
    function depositToSubVault(address vault, uint256 assets) external returns (uint256 shares);

    /**
     * @notice Function to enter sub-vault exit queue. Can only be called by SubVaultsRegistry contract.
     * @param vault The address of the sub-vault
     * @param shares The amount of shares to exit
     * @return positionTicket The position ticket in the exit queue
     */
    function enterSubVaultExitQueue(address vault, uint256 shares) external returns (uint256 positionTicket);

    /**
     * @notice Function to claim exited assets from a sub-vault. Can only be called by SubVaultsRegistry contract.
     * @param vault The address of the sub-vault
     * @param positionTicket The position ticket in the exit queue
     * @param timestamp The timestamp of the exit request
     * @param exitQueueIndex The index of the exit queue
     */
    function claimSubVaultExitedAssets(address vault, uint256 positionTicket, uint256 timestamp, uint256 exitQueueIndex)
        external;

    /**
     * @notice Function to mint osToken for a sub-vault. Can only be called by SubVaultsRegistry contract.
     * @param vault The address of the sub-vault
     * @param receiver The address that will receive the minted osToken shares
     * @param osTokenShares The amount of osToken shares to mint
     */
    function mintSubVaultOsToken(address vault, address receiver, uint256 osTokenShares) external;

    /**
     * @notice Function to redeem osToken from a sub-vault. Can only be called by SubVaultsRegistry contract.
     * @param vault The address of the sub-vault
     * @param redeemer The address of the OsToken redeemer
     * @param osTokenShares The amount of osToken shares to redeem
     * @return assets The amount of assets redeemed
     */
    function redeemSubVaultOsToken(address vault, address redeemer, uint256 osTokenShares)
        external
        returns (uint256 assets);
}
