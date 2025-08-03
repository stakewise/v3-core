// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IVaultOsToken} from "../interfaces/IVaultOsToken.sol";
import {IOsTokenRedeemer} from "../interfaces/IOsTokenRedeemer.sol";
import {IVaultsRegistry} from "../interfaces/IVaultsRegistry.sol";
import {Errors} from "../libraries/Errors.sol";
import {Multicall} from "../base/Multicall.sol";

/**
 * @title OsTokenRedeemer
 * @author StakeWise
 * @notice This contract is used to redeem OsTokens for the underlying asset.
 */
contract OsTokenRedeemer is Ownable2Step, Multicall, IOsTokenRedeemer {
    IVaultsRegistry private immutable _vaultsRegistry;
    IERC20 private immutable _osToken;
    uint256 private immutable _positionsUpdateDelay;

    /// @inheritdoc IOsTokenRedeemer
    address public override redeemer;

    /// @inheritdoc IOsTokenRedeemer
    address public override positionsManager;

    RedeemablePositions private _redeemablePositions;
    RedeemablePositions private _pendingRedeemablePositions;

    uint256 private _pendingPositionsTimestamp;
    uint256 private _nonce;

    mapping(uint256 nonce => mapping(bytes32 leaf => uint256 osTokenShares)) private _redeemedOsTokenShares;

    /**
     * @dev Constructor
     * @param vaultsRegistry_ The address of the VaultsRegistry contract
     * @param osToken_ The address of the OsToken contract
     * @param owner_ The address of the owner
     * @param positionsUpdateDelay_ The delay in seconds for positions updates
     */
    constructor(address vaultsRegistry_, address osToken_, address owner_, uint256 positionsUpdateDelay_)
        Ownable(owner_)
    {
        _vaultsRegistry = IVaultsRegistry(vaultsRegistry_);
        _osToken = IERC20(osToken_);
        _positionsUpdateDelay = positionsUpdateDelay_;
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
    function setRedeemer(address redeemer_) external override onlyOwner {
        if (redeemer_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (redeemer_ == redeemer) {
            revert Errors.ValueNotChanged();
        }
        redeemer = redeemer_;
        emit RedeemerUpdated(redeemer_);
    }

    /// @inheritdoc IOsTokenRedeemer
    function proposeRedeemablePositions(RedeemablePositions calldata newPositions) external override {
        if (msg.sender != positionsManager) {
            revert Errors.AccessDenied();
        }
        if (newPositions.merkleRoot == bytes32(0) || bytes(newPositions.ipfsHash).length == 0) {
            revert Errors.InvalidRedeemablePositions();
        }
        if (_pendingRedeemablePositions.merkleRoot != bytes32(0)) {
            revert Errors.RedeemablePositionsProposed();
        }
        if (newPositions.merkleRoot == _redeemablePositions.merkleRoot) {
            revert Errors.ValueNotChanged();
        }

        // update state
        _pendingRedeemablePositions = newPositions;
        _pendingPositionsTimestamp = block.timestamp;

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
        if (block.timestamp < _pendingPositionsTimestamp + _positionsUpdateDelay) {
            revert Errors.TooEarlyUpdate();
        }

        // update state
        _nonce += 1;
        _redeemablePositions = newPositions;
        delete _pendingRedeemablePositions;
        delete _pendingPositionsTimestamp;

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
        delete _pendingPositionsTimestamp;

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
    function redeemOsTokenPositions(
        OsTokenPosition[] memory positions,
        bytes32[] calldata proof,
        bool[] calldata proofFlags
    ) external override {
        if (msg.sender != redeemer) {
            revert Errors.AccessDenied();
        }

        // SLOAD to memory
        bytes32 _positionsRoot = _redeemablePositions.merkleRoot;
        if (_positionsRoot == bytes32(0)) {
            revert Errors.InvalidRedeemablePositions();
        }

        // calculate leaves and total osTokenShares to redeem
        uint256 totalOsTokenSharesToRedeem;
        uint256 positionsCount = positions.length;
        bytes32[] memory leaves = new bytes32[](positionsCount);
        for (uint256 i = 0; i < positionsCount;) {
            OsTokenPosition memory position = positions[i];

            // validate owner
            if (position.owner == address(0)) {
                revert Errors.ZeroAddress();
            }

            // validate vault
            if (position.vault == address(0) || !_vaultsRegistry.vaults(position.vault)) {
                revert Errors.InvalidVault();
            }

            // calculate leaf
            bytes32 leaf =
                keccak256(bytes.concat(keccak256(abi.encode(position.vault, position.osTokenShares, position.owner))));

            // calculate osToken shares to redeem
            uint256 nonce = _nonce;
            uint256 redeemableOsTokenShares = position.osTokenShares - _redeemedOsTokenShares[nonce][leaf];
            position.osTokenSharesToRedeem = Math.min(
                Math.min(redeemableOsTokenShares, position.osTokenSharesToRedeem),
                IVaultOsToken(position.vault).osTokenPositions(position.owner)
            );
            if (position.osTokenSharesToRedeem == 0) {
                revert Errors.InvalidShares();
            }

            // update state
            leaves[i] = leaf;
            positions[i] = position;
            unchecked {
                // cannot realistically overflow
                totalOsTokenSharesToRedeem += position.osTokenSharesToRedeem;
                _redeemedOsTokenShares[nonce][leaf] += position.osTokenSharesToRedeem;
                ++i;
            }
        }

        // verify the proof
        if (!MerkleProof.multiProofVerifyCalldata(proof, proofFlags, _positionsRoot, leaves)) {
            revert Errors.InvalidProof();
        }

        // transfer redeemed osToken shares
        SafeERC20.safeTransferFrom(_osToken, msg.sender, address(this), totalOsTokenSharesToRedeem);

        // redeem positions
        for (uint256 i = 0; i < positionsCount;) {
            OsTokenPosition memory position = positions[i];
            // redeem osToken shares
            IVaultOsToken(position.vault).redeemOsToken(position.osTokenSharesToRedeem, position.owner, msg.sender);

            unchecked {
                // cannot realistically overflow
                ++i;
            }
        }
    }
}
