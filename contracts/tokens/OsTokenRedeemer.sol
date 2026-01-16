// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Multicall} from "../base/Multicall.sol";
import {IMetaVault} from "../interfaces/IMetaVault.sol";
import {IOsTokenRedeemer} from "../interfaces/IOsTokenRedeemer.sol";
import {IOsTokenVaultController} from "../interfaces/IOsTokenVaultController.sol";
import {IVaultOsToken} from "../interfaces/IVaultOsToken.sol";
import {IVaultSubVaults} from "../interfaces/IVaultSubVaults.sol";
import {IVaultsRegistry} from "../interfaces/IVaultsRegistry.sol";
import {Errors} from "../libraries/Errors.sol";
import {ExitQueue} from "../libraries/ExitQueue.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title OsTokenRedeemer
 * @author StakeWise
 * @notice This contract is used to redeem OsTokens for the underlying asset.
 */
abstract contract OsTokenRedeemer is Ownable2Step, Multicall, IOsTokenRedeemer {
    IVaultsRegistry private immutable _vaultsRegistry;
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
    ExitQueue.History private _exitQueue;

    /**
     * @dev Constructor
     * @param vaultsRegistry_ The address of the VaultsRegistry contract
     * @param osToken_ The address of the OsToken contract
     * @param osTokenVaultController_ The address of the OsTokenVaultController contract
     * @param owner_ The address of the owner
     * @param exitQueueUpdateDelay_ The delay in seconds for exit queue updates
     */
    constructor(
        address vaultsRegistry_,
        address osToken_,
        address osTokenVaultController_,
        address owner_,
        uint256 exitQueueUpdateDelay_
    ) Ownable(owner_) {
        if (exitQueueUpdateDelay_ > type(uint64).max) {
            revert Errors.InvalidDelay();
        }
        _vaultsRegistry = IVaultsRegistry(vaultsRegistry_);
        _osToken = IERC20(osToken_);
        _osTokenVaultController = IOsTokenVaultController(osTokenVaultController_);
        exitQueueUpdateDelay = exitQueueUpdateDelay_;
    }

    /// @inheritdoc IOsTokenRedeemer
    function getExitQueueData() public view override returns (uint256, uint256, uint256) {
        return (
            queuedShares,
            unclaimedAssets + redeemedAssets + swappedAssets,
            ExitQueue.getLatestTotalTickets(_exitQueue) + redeemedShares + swappedShares
        );
    }

    /// @inheritdoc IOsTokenRedeemer
    function getExitQueueCumulativeTickets() external view override returns (uint256) {
        (uint256 _queuedShares, , uint256 totalTickets) = getExitQueueData();
        return totalTickets + _queuedShares;
    }

    /// @inheritdoc IOsTokenRedeemer
    function redeemablePositions() external view override returns (bytes32 merkleRoot, string memory ipfsHash) {
        merkleRoot = _redeemablePositions.merkleRoot;
        ipfsHash = _redeemablePositions.ipfsHash;
    }

    /// @inheritdoc IOsTokenRedeemer
    function getExitQueueIndex(
        uint256 positionTicket
    ) external view override returns (int256) {
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
    function calculateExitedAssets(
        address receiver,
        uint256 positionTicket,
        uint256 exitQueueIndex
    ) public view override returns (uint256 leftTickets, uint256 exitedTickets, uint256 exitedAssets) {
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
    function setPositionsManager(
        address positionsManager_
    ) external override onlyOwner {
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
    function getExitQueueMissingAssets(
        uint256 targetCumulativeTickets
    ) external view override returns (uint256 missingAssets) {
        // SLOAD to memory
        (uint256 _queuedShares, uint256 _unclaimedAssets, uint256 totalTickets) = getExitQueueData();

        // check whether already covered
        if (totalTickets >= targetCumulativeTickets) {
            return 0;
        }

        // calculate the amount of tickets that need to be covered
        uint256 totalTicketsToCover = targetCumulativeTickets - totalTickets;

        // calculate missing assets
        missingAssets = _osTokenVaultController.convertToAssets(Math.min(totalTicketsToCover, _queuedShares));

        // check whether there is enough available assets
        uint256 availableAssets = _availableAssets() - _unclaimedAssets;
        return availableAssets >= missingAssets ? 0 : missingAssets - availableAssets;
    }

    /// @inheritdoc IOsTokenRedeemer
    function setRedeemablePositions(
        RedeemablePositions calldata newPositions
    ) external override onlyOwner {
        if (newPositions.merkleRoot == bytes32(0) || bytes(newPositions.ipfsHash).length == 0) {
            revert Errors.InvalidRedeemablePositions();
        }

        // SLOAD to memory
        RedeemablePositions memory currentPositions = _redeemablePositions;
        if (newPositions.merkleRoot == currentPositions.merkleRoot) {
            revert Errors.ValueNotChanged();
        }

        // update state
        nonce += 1;
        _redeemablePositions = newPositions;

        // emit event
        emit RedeemablePositionsUpdated(newPositions.merkleRoot, newPositions.ipfsHash);
    }

    /// @inheritdoc IOsTokenRedeemer
    function permitOsToken(
        uint256 shares,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        try IERC20Permit(address(_osToken)).permit(msg.sender, address(this), shares, deadline, v, r, s) {} catch {}
    }

    /// @inheritdoc IOsTokenRedeemer
    function enterExitQueue(
        uint256 shares,
        address receiver
    ) external override returns (uint256 positionTicket) {
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
    function claimExitedAssets(
        uint256 positionTicket,
        uint256 exitQueueIndex
    ) external override {
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

    /// @inheritdoc IOsTokenRedeemer
    function redeemSubVaultsAssets(
        address metaVault,
        uint256 assetsToRedeem
    ) external override returns (uint256 totalRedeemedAssets) {
        if (msg.sender != positionsManager) {
            revert Errors.AccessDenied();
        }

        if (!_isMetaVault(metaVault)) {
            revert Errors.InvalidVault();
        }

        return IMetaVault(metaVault).redeemSubVaultsAssets(assetsToRedeem);
    }

    /// @inheritdoc IOsTokenRedeemer
    function redeemSubVaultOsToken(
        address subVault,
        uint256 osTokenShares
    ) external override {
        if (!_vaultsRegistry.vaults(subVault) || !_isMetaVault(msg.sender)) {
            revert Errors.AccessDenied();
        }
        if (osTokenShares == 0) {
            revert Errors.InvalidShares();
        }

        // redeem osToken shares from sub vault to meta vault
        IVaultOsToken(subVault).redeemOsToken(osTokenShares, msg.sender, msg.sender);
    }

    /// @inheritdoc IOsTokenRedeemer
    function redeemOsTokenPositions(
        OsTokenPosition[] memory positions,
        bytes32[] calldata proof,
        bool[] calldata proofFlags
    ) external override {
        if (msg.sender != positionsManager) {
            revert Errors.AccessDenied();
        }

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
                unchecked {
                    // position.sharesToRedeem <= _queuedShares checked above
                    _queuedShares -= position.sharesToRedeem;
                    // cannot realistically overflow
                    leafToProcessedShares[leaf] = processedPositionShares + position.sharesToRedeem;
                }
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

        // update state
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
    function _swapAssetsToOsTokenShares(
        address receiver,
        uint256 assets
    ) internal returns (uint256 osTokenShares) {
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
     * @dev Internal function to check whether the caller is a meta vault
     * @param vault The address of the vault to check
     * @return True if the caller is a meta vault, false otherwise
     */
    function _isMetaVault(
        address vault
    ) private view returns (bool) {
        // must be a registered vault
        if (!_vaultsRegistry.vaults(vault)) {
            return false;
        }

        // must be a meta vault
        try IVaultSubVaults(vault).getSubVaults() {
            return true;
        } catch {
            return false;
        }
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
    function _transferAssets(
        address receiver,
        uint256 assets
    ) internal virtual;
}
