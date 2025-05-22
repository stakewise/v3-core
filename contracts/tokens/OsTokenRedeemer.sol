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
    uint256 private immutable _positionsRootUpdateDelay;

    /// @inheritdoc IOsTokenRedeemer
    bytes32 public override positionsRoot;

    /// @inheritdoc IOsTokenRedeemer
    bytes32 public override pendingPositionsRoot;

    /// @inheritdoc IOsTokenRedeemer
    address public override redeemer;

    uint256 private _nonce;
    uint256 private _pendingPositionsRootTimestamp;

    mapping(uint256 nonce => mapping(bytes32 leaf => uint256 osTokenShares)) private _redeemedOsTokenShares;

    /**
     * @dev Constructor
     * @param vaultsRegistry_ The address of the VaultsRegistry contract
     * @param osToken_ The address of the OsToken contract
     * @param owner_ The address of the owner
     * @param positionsRootUpdateDelay_ The delay in seconds for updating the positions root
     */
    constructor(address vaultsRegistry_, address osToken_, address owner_, uint256 positionsRootUpdateDelay_)
        Ownable(owner_)
    {
        _vaultsRegistry = IVaultsRegistry(vaultsRegistry_);
        _osToken = IERC20(osToken_);
        _positionsRootUpdateDelay = positionsRootUpdateDelay_;
    }

    /// @inheritdoc IOsTokenRedeemer
    function initiatePositionsRootUpdate(bytes32 newPositionsRoot) external override onlyOwner {
        if (
            newPositionsRoot == bytes32(0) || newPositionsRoot == pendingPositionsRoot
                || newPositionsRoot == positionsRoot
        ) {
            revert Errors.InvalidRoot();
        }

        pendingPositionsRoot = newPositionsRoot;
        _pendingPositionsRootTimestamp = block.timestamp;

        // emit event
        emit PositionsRootUpdateInitiated(newPositionsRoot);
    }

    /// @inheritdoc IOsTokenRedeemer
    function applyPositionsRootUpdate() external override onlyOwner {
        // SLOAD to memory
        bytes32 _pendingPositionsRoot = pendingPositionsRoot;

        if (_pendingPositionsRoot == bytes32(0)) {
            revert Errors.InvalidRoot();
        }
        if (block.timestamp < _pendingPositionsRootTimestamp + _positionsRootUpdateDelay) {
            revert Errors.TooEarlyUpdate();
        }
        positionsRoot = _pendingPositionsRoot;
        _nonce++;

        delete pendingPositionsRoot;
        delete _pendingPositionsRootTimestamp;
        emit PositionsRootUpdated(_pendingPositionsRoot);
    }

    /// @inheritdoc IOsTokenRedeemer
    function cancelPositionsRootUpdate() external override onlyOwner {
        // SLOAD to memory
        bytes32 _pendingPositionsRoot = pendingPositionsRoot;
        if (_pendingPositionsRoot == bytes32(0)) {
            return;
        }
        delete pendingPositionsRoot;
        delete _pendingPositionsRootTimestamp;

        // emit event
        emit PositionsRootUpdateCancelled(_pendingPositionsRoot);
    }

    /// @inheritdoc IOsTokenRedeemer
    function removePositionsRoot() external override onlyOwner {
        // SLOAD to memory
        bytes32 _positionsRoot = positionsRoot;
        if (_positionsRoot == bytes32(0)) {
            return;
        }
        delete positionsRoot;
        emit PositionsRootRemoved(_positionsRoot);
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
    function redeemOsTokenPositions(
        OsTokenPosition[] memory positions,
        bytes32[] calldata proof,
        bool[] calldata proofFlags
    ) external override {
        if (msg.sender != redeemer) {
            revert Errors.AccessDenied();
        }

        // SLOAD to memory
        bytes32 _positionsRoot = positionsRoot;

        // calculate leaves and total osTokenShares to redeem
        bytes32 leaf;
        uint256 redeemableOsTokenShares;
        uint256 totalOsTokenSharesToRedeem;
        OsTokenPosition memory position;
        uint256 positionsCount = positions.length;
        bytes32[] memory leaves = new bytes32[](positionsCount);
        for (uint256 i = 0; i < positionsCount;) {
            position = positions[i];

            // validate owner
            if (position.owner == address(0)) {
                revert Errors.ZeroAddress();
            }

            // validate vault
            if (position.vault == address(0) || !_vaultsRegistry.vaults(position.vault)) {
                revert Errors.InvalidVault();
            }

            // calculate leaf
            leaf =
                keccak256(bytes.concat(keccak256(abi.encode(position.vault, position.osTokenShares, position.owner))));

            // calculate osToken shares to redeem
            uint256 nonce = _nonce;
            redeemableOsTokenShares = position.osTokenShares - _redeemedOsTokenShares[nonce][leaf];
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
            position = positions[i];
            // redeem osToken shares
            IVaultOsToken(position.vault).redeemOsToken(position.osTokenSharesToRedeem, position.owner, msg.sender);

            unchecked {
                // cannot realistically overflow
                ++i;
            }
        }
    }
}
