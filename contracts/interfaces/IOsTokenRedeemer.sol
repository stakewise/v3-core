// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IMulticall} from "./IMulticall.sol";

/**
 * @title IOsTokenRedeemer
 * @author StakeWise
 * @notice Interface for OsTokenRedeemer contract
 */
interface IOsTokenRedeemer is IMulticall {
    /**
     * @notice Struct to store the redeemable positions Merkle root and IPFS hash
     * @param merkleRoot The Merkle root of the redeemable positions
     * @param ipfsHash The IPFS hash of the redeemable positions
     */
    struct RedeemablePositions {
        bytes32 merkleRoot;
        string ipfsHash;
    }

    /**
     * @notice Struct to store the redeemed OsToken position details
     * @param vault The address of the Vault
     * @param owner The address of the position owner
     * @param leafShares The amount of OsToken shares used to calculate the merkle leaf
     * @param osTokenSharesToRedeem The amount of OsToken shares to redeem
     */
    struct OsTokenPosition {
        address vault;
        address owner;
        uint256 leafShares;
        uint256 sharesToRedeem;
    }

    /**
     * @notice Event emitted when the positions manager is updated
     * @param positionsManager The address of the new positions manager
     */
    event PositionsManagerUpdated(address indexed positionsManager);

    /**
     * @notice Event emitted when new redeemable positions are proposed
     * @param merkleRoot The Merkle root of the redeemable positions
     * @param ipfsHash The IPFS hash of the redeemable positions
     */
    event RedeemablePositionsUpdated(bytes32 indexed merkleRoot, string ipfsHash);

    /**
     * @notice Event emitted on shares added to the exit queue
     * @param owner The address that owns the shares
     * @param receiver The address that will receive withdrawn assets
     * @param positionTicket The exit queue ticket that was assigned to the position
     * @param shares The number of shares that queued for the exit
     */
    event ExitQueueEntered(address indexed owner, address indexed receiver, uint256 positionTicket, uint256 shares);

    /**
     * @notice Event emitted on claim of the exited assets
     * @param receiver The address that has received withdrawn assets
     * @param prevPositionTicket The exit queue ticket received after the `enterExitQueue` call
     * @param newPositionTicket The new exit queue ticket in case not all the shares were withdrawn. Otherwise 0.
     * @param withdrawnAssets The total number of assets withdrawn
     */
    event ExitedAssetsClaimed(
        address indexed receiver, uint256 prevPositionTicket, uint256 newPositionTicket, uint256 withdrawnAssets
    );

    /**
     * @notice Event emitted on shares swapped for assets
     * @param sender The address that initiated the swap
     * @param receiver The address that will receive the shares
     * @param shares The number of shares received
     * @param assets The number of assets spent
     */
    event OsTokenSharesSwapped(address indexed sender, address indexed receiver, uint256 shares, uint256 assets);

    /**
     * @notice Event emitted on checkpoint creation
     * @param shares The number of burned shares
     * @param assets The amount of exited assets
     */
    event CheckpointCreated(uint256 shares, uint256 assets);

    /**
     * @notice Event emitted when OsToken positions are redeemed
     * @param shares The number of shares redeemed
     * @param assets The number of assets redeemed
     */
    event OsTokenPositionsRedeemed(uint256 shares, uint256 assets);

    /**
     * @notice The delay in seconds for the exit queue updates
     * @return The delay in seconds
     */
    function exitQueueUpdateDelay() external view returns (uint256);

    /**
     * @notice The number of queued OsToken shares
     * @return The number of queued shares
     */
    function queuedShares() external view returns (uint128);

    /**
     * @notice The number of unclaimed assets in the exit queue
     * @return The number of unclaimed assets
     */
    function unclaimedAssets() external view returns (uint128);

    /**
     * @notice The number of redeemed OsToken shares
     * @return The number of redeemed shares
     */
    function redeemedShares() external view returns (uint128);

    /**
     * @notice The number of redeemed assets
     * @return The number of redeemed assets
     */
    function redeemedAssets() external view returns (uint128);

    /**
     * @notice The number of swapped OsToken shares
     * @return The number of swapped shares
     */
    function swappedShares() external view returns (uint128);

    /**
     * @notice The number of swapped assets
     * @return The number of swapped assets
     */
    function swappedAssets() external view returns (uint128);

    /**
     * @notice Maps a Merkle tree leaf to processed shares
     * @param leaf The leaf of the Merkle tree
     * @return processedShares The number of processed shares corresponding to the leaf
     */
    function leafToProcessedShares(bytes32 leaf) external view returns (uint256 processedShares);

    /**
     * @notice Maps a exit request hash to the number of exiting shares
     * @param exitRequestHash The hash of the exit request
     * @return shares The number of shares that are exiting for the given exit request hash
     */
    function exitRequests(bytes32 exitRequestHash) external view returns (uint256 shares);

    /**
     * @notice The timestamp when the exit queue was last updated
     * @return The timestamp of the last exit queue update
     */
    function exitQueueTimestamp() external view returns (uint256);

    /**
     * @notice The address authorized to redeem OsToken positions
     * @return The address of the redeemer
     */
    function positionsManager() external view returns (address);

    /**
     * @notice The current nonce for the redemptions
     * @return The current nonce value
     */
    function nonce() external view returns (uint256);

    /**
     * @notice Get the current exit queue data
     * @return queuedShares The total number of shares currently queued for exit
     * @return unclaimedAssets The total number of assets that have not been claimed yet
     * @return totalTickets The total number of tickets (shares) processed in the exit queue
     */
    function getExitQueueData()
        external
        view
        returns (uint256 queuedShares, uint256 unclaimedAssets, uint256 totalTickets);

    /**
     * @notice Calculates the missing assets in the exit queue for a target cumulative tickets.
     * @param targetCumulativeTickets The target cumulative tickets in the exit queue
     * @return missingAssets The number of missing assets in the exit queue
     */
    function getExitQueueMissingAssets(uint256 targetCumulativeTickets) external view returns (uint256 missingAssets);

    /**
     * @notice Checks if the exit queue can be processed
     * @return True if the exit queue can be processed, false otherwise
     */
    function canProcessExitQueue() external view returns (bool);

    /**
     * @notice The current redeemable positions Merkle root and IPFS hash
     * @return merkleRoot The Merkle root of the redeemable positions
     * @return ipfsHash The IPFS hash of the redeemable positions
     */
    function redeemablePositions() external view returns (bytes32 merkleRoot, string memory ipfsHash);

    /**
     * @notice Gets the index of the exit queue for a given position ticket.
     * @param positionTicket The position ticket to search for
     * @return The index of the exit queue or -1 if not found
     */
    function getExitQueueIndex(uint256 positionTicket) external view returns (int256);

    /**
     * @notice Calculates the exited assets for a given position ticket and exit queue index.
     * @param receiver The address of the receiver
     * @param positionTicket The position ticket to calculate exited assets for
     * @param exitQueueIndex The index of the exit queue to calculate exited assets for
     * @return leftTickets The number of tickets left in the exit queue
     * @return exitedTickets The number of tickets that have exited
     * @return exitedAssets The number of assets that have exited
     */
    function calculateExitedAssets(address receiver, uint256 positionTicket, uint256 exitQueueIndex)
        external
        view
        returns (uint256 leftTickets, uint256 exitedTickets, uint256 exitedAssets);

    /**
     * @notice Update the address of the positions manager. Can only be called by the owner.
     * @param positionsManager_ The address of the new positions manager
     */
    function setPositionsManager(address positionsManager_) external;

    /**
     * @notice Set new redeemable positions. Can only be called by the owner.
     * @param newPositions The new redeemable positions
     */
    function setRedeemablePositions(RedeemablePositions calldata newPositions) external;

    /**
     * @notice Permit OsToken shares to be used for redemption.
     * @param shares The number of shares to permit
     * @param deadline The deadline for the permit
     * @param v The recovery byte of the signature
     * @param r The output of the ECDSA signature
     * @param s The output of the ECDSA signature
     */
    function permitOsToken(uint256 shares, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;

    /**
     * @notice Enters the exit queue with a given number of shares and receiver address.
     * @param shares The number of shares to enter the exit queue with
     * @param receiver The address that will receive the assets after exit
     * @return positionTicket The position ticket for the entered exit queue
     */
    function enterExitQueue(uint256 shares, address receiver) external returns (uint256 positionTicket);

    /**
     * @notice Claims exited assets for a given position ticket and exit queue index.
     * @param positionTicket The position ticket to claim exited assets for
     * @param exitQueueIndex The index of the exit queue to claim exited assets for
     */
    function claimExitedAssets(uint256 positionTicket, uint256 exitQueueIndex) external;

    /**
     * @notice Redeem OsToken shares from a specific sub-vault. Can only be called by the meta vault.
     * @param subVault The address of the sub-vault
     * @param osTokenShares The number of OsToken shares to redeem
     */
    function redeemSubVaultOsToken(address subVault, uint256 osTokenShares) external;

    /**
     * @notice Redeem assets from the sub-vaults to the meta vault. Can only be called by the positions manager.
     * @param metaVault The address of the meta vault
     * @param assetsToRedeem The number of assets to redeem
     * @return totalRedeemedAssets The total number of redeemed assets
     */
    function redeemSubVaultsAssets(address metaVault, uint256 assetsToRedeem)
        external
        returns (uint256 totalRedeemedAssets);

    /**
     * @notice Redeem OsToken shares from the vault positions.
     * @param positions The array of OsToken positions to redeem
     * @param proof The Merkle proof for the positions root
     * @param proofFlags The flags for the Merkle proof
     */
    function redeemOsTokenPositions(
        OsTokenPosition[] memory positions,
        bytes32[] calldata proof,
        bool[] calldata proofFlags
    ) external;

    /**
     * @notice Process the exit queue and checkpoint swapped or redeemed shares. Can only be called once per `exitQueueUpdateDelay`.
     */
    function processExitQueue() external;
}
