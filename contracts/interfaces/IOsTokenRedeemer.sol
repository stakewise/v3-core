// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

/**
 * @title IOsTokenRedeemer
 * @author StakeWise
 * @notice Interface for OsTokenRedeemer contract
 */
interface IOsTokenRedeemer {
    /**
     * @notice Struct to store the redeemed OsToken position details
     * @param vault The address of the Vault
     * @param owner The address of the position owner
     * @param osTokenShares The amount of OsToken shares that can be redeemed in total
     * @param osTokenSharesToRedeem The amount of OsToken shares to redeem
     */
    struct OsTokenPosition {
        address vault;
        address owner;
        uint256 osTokenShares;
        uint256 osTokenSharesToRedeem;
    }

    /**
     * @notice Event emitted when the positions root update is initiated
     * @param newPositionsRoot The new positions root
     */
    event PositionsRootUpdateInitiated(bytes32 newPositionsRoot);

    /**
     * @notice Event emitted when the positions root is updated
     * @param newPositionsRoot The new positions root
     */
    event PositionsRootUpdated(bytes32 newPositionsRoot);

    /**
     * @notice Event emitted when the positions root update is cancelled
     * @param positionsRoot The positions root that was cancelled
     */
    event PositionsRootUpdateCancelled(bytes32 positionsRoot);

    /**
     * @notice Event emitted when the positions root is removed
     * @param positionsRoot The positions root that was removed
     */
    event PositionsRootRemoved(bytes32 positionsRoot);

    /**
     * @notice Event emitted when the redeemer is updated
     * @param newRedeemer The address of the new redeemer
     */
    event RedeemerUpdated(address newRedeemer);

    /**
     * @notice The address that can redeem OsToken positions
     */
    function redeemer() external view returns (address);

    /**
     * @notice The positions Merkle root used for verifying redemptions
     * @return The positions root
     */
    function positionsRoot() external view returns (bytes32);

    /**
     * @notice The pending positions Merkle root that is waiting for the delay to pass
     * @return The pending positions root
     */
    function pendingPositionsRoot() external view returns (bytes32);

    /**
     * @notice Initiates the update of the positions root
     * @param newPositionsRoot The new positions root
     */
    function initiatePositionsRootUpdate(bytes32 newPositionsRoot) external;

    /**
     * @notice Applies the update of the positions root
     */
    function applyPositionsRootUpdate() external;

    /**
     * @notice Cancels the update of the positions root
     */
    function cancelPositionsRootUpdate() external;

    /**
     * @notice Removes the current positions root
     */
    function removePositionsRoot() external;

    /**
     * @notice Update the address of the redeemer
     * @param newRedeemer The address of the new redeemer
     */
    function setRedeemer(address newRedeemer) external;

    /**
     * @notice Redeems OsToken positions
     * @param positions The array of OsToken positions to redeem
     * @param proof The Merkle proof for the positions root
     * @param proofFlags The flags for the Merkle proof
     */
    function redeemOsTokenPositions(
        OsTokenPosition[] memory positions,
        bytes32[] calldata proof,
        bool[] calldata proofFlags
    ) external;
}
