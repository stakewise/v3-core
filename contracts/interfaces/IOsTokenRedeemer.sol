// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

/**
 * @title IOsTokenRedeemer
 * @author StakeWise
 * @notice Interface for OsTokenRedeemer contract
 */
interface IOsTokenRedeemer {
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
     * @notice Event emitted when the redeemer is updated
     * @param newRedeemer The address of the new redeemer
     */
    event RedeemerUpdated(address newRedeemer);

    /**
     * @notice Event emitted when the positions manager is updated
     * @param positionsManager The address of the new positions manager
     */
    event PositionsManagerUpdated(address positionsManager);

    /**
     * @notice Event emitted when new redeemable positions are proposed
     * @param merkleRoot The Merkle root of the redeemable positions
     * @param ipfsHash The IPFS hash of the redeemable positions
     */
    event RedeemablePositionsProposed(bytes32 merkleRoot, string ipfsHash);

    /**
     * @notice Event emitted when the pending redeemable positions are accepted
     * @param merkleRoot The Merkle root of the accepted redeemable positions
     * @param ipfsHash The IPFS hash of the accepted redeemable positions
     */
    event RedeemablePositionsAccepted(bytes32 merkleRoot, string ipfsHash);

    /**
     * @notice Event emitted when the new redeemable positions are denied
     * @param merkleRoot The Merkle root of the denied redeemable positions
     * @param ipfsHash The IPFS hash of the denied redeemable positions
     */
    event RedeemablePositionsDenied(bytes32 merkleRoot, string ipfsHash);

    /**
     * @notice Event emitted when the redeemable positions are removed
     * @param merkleRoot The Merkle root of the removed redeemable positions
     * @param ipfsHash The IPFS hash of the removed redeemable positions
     */
    event RedeemablePositionsRemoved(bytes32 merkleRoot, string ipfsHash);

    /**
     * @notice The address that can redeem OsToken positions
     * @return The address of the redeemer
     */
    function redeemer() external view returns (address);

    /**
     * @notice The address that manages redeemable OsToken positions
     * @return The address of the positions manager
     */
    function positionsManager() external view returns (address);

    /**
     * @notice The current redeemable positions Merkle root and IPFS hash
     * @return merkleRoot The Merkle root of the redeemable positions
     * @return ipfsHash The IPFS hash of the redeemable positions
     */
    function redeemablePositions() external view returns (bytes32 merkleRoot, string memory ipfsHash);

    /**
     * @notice The pending redeemable positions Merkle root and IPFS hash that is waiting to be accepted
     * @return merkleRoot The Merkle root of the pending redeemable positions
     * @return ipfsHash The IPFS hash of the pending redeemable positions
     */
    function pendingRedeemablePositions() external view returns (bytes32 merkleRoot, string memory ipfsHash);

    /**
     * @notice Update the address of the redeemer. Can only be called by the owner.
     * @param newRedeemer The address of the new redeemer
     */
    function setRedeemer(address newRedeemer) external;

    /**
     * @notice Update the address of the positions manager. Can only be called by the owner.
     * @param positionsManager_ The address of the new positions manager
     */
    function setPositionsManager(address positionsManager_) external;

    /**
     * @notice Proposes new redeemable positions. Can only be called by the positions manager.
     * @param newPositions The new redeemable positions to propose
     */
    function proposeRedeemablePositions(RedeemablePositions calldata newPositions) external;

    /**
     * @notice Accepts the pending redeemable positions. Can only be called by the owner.
     */
    function acceptRedeemablePositions() external;

    /**
     * @notice Denies the pending redeemable positions. Can only be called by the owner.
     */
    function denyRedeemablePositions() external;

    /**
     * @notice Removes the redeemable positions. Can only be called by the owner.
     */
    function removeRedeemablePositions() external;

    /**
     * @notice Redeems OsToken positions. Can only be called by the redeemer.
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
