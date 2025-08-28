// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IVaultOsToken} from "../interfaces/IVaultOsToken.sol";
import {IOsTokenVaultController} from "../interfaces/IOsTokenVaultController.sol";
import {IOsTokenRedeemer} from "../interfaces/IOsTokenRedeemer.sol";
import {Errors} from "../libraries/Errors.sol";
import {ExitQueue} from "../libraries/ExitQueue.sol";
import {Multicall} from "../base/Multicall.sol";

/**
 * @title OsTokenRedeemer
 * @author StakeWise
 * @notice This contract is used to redeem OsTokens for the underlying asset.
 */
abstract contract OsTokenRedeemer is Ownable2Step, Multicall, IOsTokenRedeemer {
    IERC20 private immutable _osToken;
    IOsTokenVaultController private immutable _osTokenVaultController;

    /// @inheritdoc IOsTokenRedeemer
    uint256 public immutable override exitQueueUpdateDelay;

    /// @inheritdoc IOsTokenRedeemer
    address public override positionsManager;

    /// @inheritdoc IOsTokenRedeemer
    uint256 public override nonce;

    /// @inheritdoc IOsTokenRedeemer
    uint128 public override queuedShares;

    /// @inheritdoc IOsTokenRedeemer
    uint128 public override unclaimedAssets;

    /// @inheritdoc IOsTokenRedeemer
    uint128 public override redeemedShares;

    /// @inheritdoc IOsTokenRedeemer
    uint128 public override redeemedAssets;

    /// @inheritdoc IOsTokenRedeemer
    uint128 public override swappedShares;

    /// @inheritdoc IOsTokenRedeemer
    uint128 public override swappedAssets;

    /// @inheritdoc IOsTokenRedeemer
    mapping(bytes32 leaf => uint256 processedShares) public override leafToProcessedShares;

    /// @inheritdoc IOsTokenRedeemer
    mapping(bytes32 exitRequestHash => uint256 shares) public override exitRequests;

    /// @inheritdoc IOsTokenRedeemer
    uint256 public override exitQueueTimestamp;

    RedeemablePositions private _redeemablePositions;
    RedeemablePositions private _pendingRedeemablePositions;
    ExitQueue.History private _exitQueue;

    /**
     * @dev Constructor
     * @param osToken_ The address of the OsToken contract
     * @param osTokenVaultController_ The address of the OsTokenVaultController contract
     * @param owner_ The address of the owner
     * @param exitQueueUpdateDelay_ The delay in seconds for exit queue updates
     */
    constructor(address osToken_, address osTokenVaultController_, address owner_, uint256 exitQueueUpdateDelay_)
        Ownable(owner_)
    {
        if (exitQueueUpdateDelay_ > type(uint64).max) {
            revert Errors.InvalidDelay();
        }
        _osToken = IERC20(osToken_);
        _osTokenVaultController = IOsTokenVaultController(osTokenVaultController_);
        exitQueueUpdateDelay = exitQueueUpdateDelay_;
    }

    /// @inheritdoc IOsTokenRedeemer
    function getExitQueueData() external view override returns (uint256, uint256, uint256) {
        return (
            queuedShares,
            unclaimedAssets + redeemedAssets + swappedAssets,
            ExitQueue.getLatestTotalTickets(_exitQueue) + redeemedShares + swappedShares
        );
    }

    /// @inheritdoc IOsTokenRedeemer
    function redeemablePositions() external view override returns (bytes32 merkleRoot, string memory ipfsHash) {
        merkleRoot = _redeemablePositions.merkleRoot;
        ipfsHash = _redeemablePositions.ipfsHash;
    }

    /// @inheritdoc IOsTokenRedeemer
    function pendingRedeemablePositions() external view override returns (bytes32 merkleRoot, string memory ipfsHash) {
        merkleRoot = _pendingRedeemablePositions.merkleRoot;
        ipfsHash = _pendingRedeemablePositions.ipfsHash;
    }

    /// @inheritdoc IOsTokenRedeemer
    function getExitQueueIndex(uint256 positionTicket) external view override returns (int256) {
        uint256 checkpointIdx = ExitQueue.getCheckpointIndex(_exitQueue, positionTicket);
        return checkpointIdx < _exitQueue.checkpoints.length ? int256(checkpointIdx) : -1;
    }

    /// @inheritdoc IOsTokenRedeemer
    function canProcessExitQueue() external view override returns (bool) {
        if (exitQueueTimestamp + exitQueueUpdateDelay > block.timestamp) {
            return false;
        }
        return swappedShares > 0 || redeemedShares > 0;
    }

    /// @inheritdoc IOsTokenRedeemer
    function calculateExitedAssets(address receiver, uint256 positionTicket, uint256 exitQueueIndex)
        public
        view
        override
        returns (uint256 leftTickets, uint256 exitedTickets, uint256 exitedAssets)
    {
        uint256 exitingTickets = exitRequests[keccak256(abi.encode(receiver, positionTicket))];
        if (exitingTickets == 0) return (0, 0, 0);

        // calculate exited tickets and assets
        (exitedTickets, exitedAssets) =
            ExitQueue.calculateExitedAssets(_exitQueue, exitQueueIndex, positionTicket, exitingTickets);
        leftTickets = exitingTickets - exitedTickets;
        if (leftTickets == 1) {
            // if only one ticket is left round it to zero
            leftTickets = 0;
            exitedTickets += 1; // round up exited tickets
        }
    }

    /// @inheritdoc IOsTokenRedeemer
    function setPositionsManager(address positionsManager_) external override onlyOwner {
        if (positionsManager_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (positionsManager_ == positionsManager) {
            revert Errors.ValueNotChanged();
        }
        positionsManager = positionsManager_;
        emit PositionsManagerUpdated(positionsManager_);
    }

    /// @inheritdoc IOsTokenRedeemer
    function proposeRedeemablePositions(RedeemablePositions calldata newPositions) external override {
        if (msg.sender != positionsManager) {
            revert Errors.AccessDenied();
        }
        if (newPositions.merkleRoot == bytes32(0) || bytes(newPositions.ipfsHash).length == 0) {
            revert Errors.InvalidRedeemablePositions();
        }

        // SLOAD to memory
        RedeemablePositions memory pendingPositions = _pendingRedeemablePositions;
        if (pendingPositions.merkleRoot != bytes32(0) || bytes(pendingPositions.ipfsHash).length != 0) {
            revert Errors.RedeemablePositionsProposed();
        }

        // SLOAD to memory
        RedeemablePositions memory currentPositions = _redeemablePositions;
        if (newPositions.merkleRoot == currentPositions.merkleRoot || bytes(pendingPositions.ipfsHash).length != 0) {
            revert Errors.ValueNotChanged();
        }

        // update state
        _pendingRedeemablePositions = newPositions;

        // emit event
        emit RedeemablePositionsProposed(newPositions.merkleRoot, newPositions.ipfsHash);
    }

    /// @inheritdoc IOsTokenRedeemer
    function acceptRedeemablePositions() external override onlyOwner {
        // SLOAD to memory
        RedeemablePositions memory newPositions = _pendingRedeemablePositions;
        if (newPositions.merkleRoot == bytes32(0) || bytes(newPositions.ipfsHash).length == 0) {
            revert Errors.InvalidRedeemablePositions();
        }

        // update state
        nonce += 1;
        _redeemablePositions = newPositions;
        delete _pendingRedeemablePositions;

        // emit event
        emit RedeemablePositionsAccepted(newPositions.merkleRoot, newPositions.ipfsHash);
    }

    /// @inheritdoc IOsTokenRedeemer
    function denyRedeemablePositions() external override onlyOwner {
        // SLOAD to memory
        RedeemablePositions memory newPositions = _pendingRedeemablePositions;
        if (newPositions.merkleRoot == bytes32(0)) {
            return;
        }
        delete _pendingRedeemablePositions;

        // emit event
        emit RedeemablePositionsDenied(newPositions.merkleRoot, newPositions.ipfsHash);
    }

    /// @inheritdoc IOsTokenRedeemer
    function removeRedeemablePositions() external override onlyOwner {
        // SLOAD to memory
        RedeemablePositions memory positions = _redeemablePositions;
        if (positions.merkleRoot == bytes32(0)) {
            return;
        }

        delete _redeemablePositions;
        emit RedeemablePositionsRemoved(positions.merkleRoot, positions.ipfsHash);
    }

    /// @inheritdoc IOsTokenRedeemer
    function permitOsToken(uint256 shares, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external override {
        try IERC20Permit(address(_osToken)).permit(msg.sender, address(this), shares, deadline, v, r, s) {} catch {}
    }

    /// @inheritdoc IOsTokenRedeemer
    function enterExitQueue(uint256 shares, address receiver) external override returns (uint256 positionTicket) {
        if (shares == 0) revert Errors.InvalidShares();
        if (receiver == address(0)) revert Errors.ZeroAddress();

        // SLOAD to memory
        uint256 _queuedShares = queuedShares;

        // calculate position ticket
        positionTicket = ExitQueue.getLatestTotalTickets(_exitQueue) + swappedShares + redeemedShares + _queuedShares;

        // add to the exit requests
        exitRequests[keccak256(abi.encode(receiver, positionTicket))] = shares;

        // reverts if owner does not have enough shares
        SafeERC20.safeTransferFrom(_osToken, msg.sender, address(this), shares);

        unchecked {
            // cannot overflow as it is capped with OsToken total supply
            queuedShares = SafeCast.toUint128(_queuedShares + shares);
        }

        // emit event
        emit ExitQueueEntered(msg.sender, receiver, positionTicket, shares);
    }

    /// @inheritdoc IOsTokenRedeemer
    function claimExitedAssets(uint256 positionTicket, uint256 exitQueueIndex) external override {
        // calculate exited tickets and assets
        (uint256 leftTickets, uint256 exitedTickets, uint256 exitedAssets) =
            calculateExitedAssets(msg.sender, positionTicket, exitQueueIndex);
        if (exitedTickets == 0 || exitedAssets == 0) {
            revert Errors.ExitRequestNotProcessed();
        }

        // update unclaimed assets
        unclaimedAssets -= SafeCast.toUint128(exitedAssets);

        // clean up current exit request
        delete exitRequests[keccak256(abi.encode(msg.sender, positionTicket))];

        // create new position if there are left tickets
        uint256 newPositionTicket;
        if (leftTickets > 0) {
            // update user's queue position
            newPositionTicket = positionTicket + exitedTickets;
            exitRequests[keccak256(abi.encode(msg.sender, newPositionTicket))] = leftTickets;
        }

        // transfer assets to the receiver
        _transferAssets(msg.sender, exitedAssets);
        emit ExitedAssetsClaimed(msg.sender, positionTicket, newPositionTicket, exitedAssets);
    }

    function redeemOsTokenPositions(
        OsTokenPosition[] memory positions,
        bytes32[] calldata proof,
        bool[] calldata proofFlags
    ) external override {
        // SLOAD to memory
        uint256 _queuedShares = queuedShares;
        uint256 positionsCount = positions.length;
        if (_queuedShares == 0 || positionsCount == 0) {
            return; // nothing to redeem
        }

        // calculate leaves and total osTokenShares to redeem
        bytes32[] memory leaves = new bytes32[](positionsCount);

        // SLOAD to memory
        uint256 _nonce = nonce - 1; // use nonce - 1 to match the leaf calculation
        for (uint256 i = 0; i < positionsCount;) {
            OsTokenPosition memory position = positions[i];

            // calculate leaf
            bytes32 leaf = keccak256(
                bytes.concat(keccak256(abi.encode(_nonce, position.vault, position.leafShares, position.owner)))
            );
            leaves[i] = leaf;

            // SLOAD processed osToken shares
            uint256 processedPositionShares = leafToProcessedShares[leaf];

            // calculate osToken shares to redeem and corresponding assets
            uint256 sharesToRedeem = Math.min(
                Math.min(position.leafShares - processedPositionShares, position.sharesToRedeem),
                Math.min(_queuedShares, IVaultOsToken(position.vault).osTokenPositions(position.owner))
            );
            position.sharesToRedeem = sharesToRedeem;

            // update state
            if (position.sharesToRedeem > 0) {
                _queuedShares -= position.sharesToRedeem;
                leafToProcessedShares[leaf] = processedPositionShares + position.sharesToRedeem;
            }

            unchecked {
                // cannot realistically overflow
                ++i;
            }
        }

        // verify the proof
        bytes32 positionsRoot = _redeemablePositions.merkleRoot;
        if (positionsRoot == bytes32(0)) {
            revert Errors.InvalidRedeemablePositions();
        }
        if (!MerkleProof.multiProofVerifyCalldata(proof, proofFlags, positionsRoot, leaves)) {
            revert Errors.InvalidProof();
        }

        // redeem positions
        uint256 availableAssetsBefore = _availableAssets();
        for (uint256 i = 0; i < positionsCount;) {
            OsTokenPosition memory position = positions[i];
            if (position.sharesToRedeem > 0) {
                // redeem osToken shares
                IVaultOsToken(position.vault).redeemOsToken(position.sharesToRedeem, position.owner, address(this));
            }

            unchecked {
                // cannot realistically overflow
                ++i;
            }
        }

        // calculate processed assets and shares
        uint256 processedAssets = _availableAssets() - availableAssetsBefore;
        uint256 processedShares = queuedShares - _queuedShares;

        // update state
        redeemedShares += SafeCast.toUint128(processedShares);
        redeemedAssets += SafeCast.toUint128(processedAssets);
        queuedShares = SafeCast.toUint128(_queuedShares);

        // emit event
        emit OsTokenPositionsRedeemed(processedShares, processedAssets);
    }

    /// @inheritdoc IOsTokenRedeemer
    function processExitQueue() external override {
        if (exitQueueTimestamp + exitQueueUpdateDelay > block.timestamp) {
            revert Errors.TooEarlyUpdate();
        }

        uint256 processedShares = swappedShares + redeemedShares;
        uint256 processedAssets = swappedAssets + redeemedAssets;
        swappedShares = 0;
        swappedAssets = 0;
        redeemedShares = 0;
        redeemedAssets = 0;

        if (processedShares == 0 || processedAssets == 0) {
            return; // nothing to process
        }

        unclaimedAssets += SafeCast.toUint128(processedAssets);

        // push checkpoint so that exited assets could be claimed
        ExitQueue.push(_exitQueue, processedShares, processedAssets);
        exitQueueTimestamp = block.timestamp;
        emit CheckpointCreated(processedShares, processedAssets);
    }

    /**
     * @dev Internal function to swap assets to OsToken shares
     * @param receiver The address that will receive the OsToken shares
     * @param assets The number of assets to swap
     * @return osTokenShares The number of OsToken shares swapped
     */
    function _swapAssetsToOsTokenShares(address receiver, uint256 assets) internal returns (uint256 osTokenShares) {
        if (assets == 0) {
            revert Errors.InvalidAssets();
        }
        if (receiver == address(0)) revert Errors.ZeroAddress();

        osTokenShares = _osTokenVaultController.convertToShares(assets);
        if (osTokenShares == 0) {
            return 0; // nothing to swap
        }

        // update state
        queuedShares -= SafeCast.toUint128(osTokenShares);
        swappedShares += SafeCast.toUint128(osTokenShares);
        swappedAssets += SafeCast.toUint128(assets);

        // transfer OsToken shares to the receiver
        SafeERC20.safeTransfer(_osToken, receiver, osTokenShares);

        // emit event
        emit OsTokenSharesSwapped(msg.sender, receiver, osTokenShares, assets);
    }

    /**
     * @dev Internal function that must be implemented to return the available assets for exit
     * @return The amount of available assets for exit
     */
    function _availableAssets() internal view virtual returns (uint256);

    /**
     * @dev Internal function for transferring assets to the receiver
     * @dev IMPORTANT: because control is transferred to the receiver, care must be
     *    taken to not create reentrancy vulnerabilities. The Vault must follow the checks-effects-interactions pattern:
     *    https://docs.soliditylang.org/en/v0.8.22/security-considerations.html#use-the-checks-effects-interactions-pattern
     * @param receiver The address that will receive the assets
     * @param assets The number of assets to transfer
     */
    function _transferAssets(address receiver, uint256 assets) internal virtual;
}
