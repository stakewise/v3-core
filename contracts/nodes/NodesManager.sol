// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {INodesManager} from "../interfaces/INodesManager.sol";
import {Errors} from "../libraries/Errors.sol";

abstract contract NodesManager is Ownable2StepUpgradeable, UUPSUpgradeable, INodesManager {
    uint256 internal constant _maxPenaltyPercent = 10_000; // @dev 100.00 %
    uint256 private constant _penaltyUpdateDelay = 3 days;
    uint256 private constant _penaltyUpdateMultiplier = 120;
    uint256 private constant _penaltyUpdateBase = 100;

    /// @inheritdoc INodesManager
    uint256 public override minBondAssets;

    /// @inheritdoc INodesManager
    uint16 public override exitPenaltyPercent;

    uint64 private _lastPenaltyUpdateTimestamp;

    /// @inheritdoc INodesManager
    uint256 public override unclaimedPenalty;

    /// @inheritdoc INodesManager
    uint256 public override depositRequestsCount;

    /// @inheritdoc INodesManager
    uint256 public override processedDepositRequestsCount;

    /// @inheritdoc INodesManager
    mapping(uint256 ticket => DepositRequest request) public override depositRequests;

    /**
     * @dev Initializes the NodesManager contract
     * @param _owner The address of the contract owner
     * @param _minBondAssets The minimum assets required for a deposit request
     * @param _exitPenaltyPercent The exit penalty percent in BPS
     */
    function __NodesManager_init(address _owner, uint256 _minBondAssets, uint16 _exitPenaltyPercent)
        internal
        onlyInitializing
    {
        __Ownable_init(_owner);
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        _setMinBondAssets(_minBondAssets);
        _setExitPenaltyPercent(_exitPenaltyPercent, true);
    }

    /// @inheritdoc INodesManager
    function setMinBondAssets(uint256 newMinBondAssets) external override onlyOwner {
        if (minBondAssets == newMinBondAssets) revert Errors.ValueNotChanged();
        _setMinBondAssets(newMinBondAssets);
    }

    /// @inheritdoc INodesManager
    function setExitPenaltyPercent(uint16 newExitPenaltyPercent) external override onlyOwner {
        if (exitPenaltyPercent == newExitPenaltyPercent) revert Errors.ValueNotChanged();
        _setExitPenaltyPercent(newExitPenaltyPercent, false);
    }

    /// @inheritdoc INodesManager
    function claimPenalty(address recipient) external override onlyOwner {
        if (recipient == address(0)) revert Errors.ZeroAddress();

        // SLOAD to memory
        uint256 assets = unclaimedPenalty;
        if (assets == 0) revert Errors.InvalidAssets();

        unclaimedPenalty = 0;
        _transferAssets(recipient, assets);
        emit PenaltyClaimed(msg.sender, recipient, assets);
    }

    /// @inheritdoc INodesManager
    function exitDepositQueue(uint256 ticket) external override {
        DepositRequest memory request = depositRequests[ticket];
        if (request.depositor != msg.sender) revert Errors.AccessDenied();

        uint256 assets = request.assets;
        if (assets == 0) revert Errors.InvalidAssets();

        uint256 penalty;
        if (ticket < processedDepositRequestsCount) {
            // skipped request — apply penalty
            penalty = Math.mulDiv(assets, exitPenaltyPercent, _maxPenaltyPercent);
            unchecked {
                assets -= penalty;
            }
            unclaimedPenalty += penalty;
        }

        delete depositRequests[ticket];
        _transferAssets(msg.sender, assets);
        emit DepositQueueExited(msg.sender, ticket, assets, penalty);
    }

    /**
     * @dev Enters the deposit queue with the given assets
     * @param assets The amount of assets to deposit
     * @return ticket The deposit queue ticket assigned to the request
     */
    function _enterDepositQueue(uint256 assets) internal returns (uint256 ticket) {
        if (assets < minBondAssets) revert Errors.InvalidAssets();

        // store the sender address and the deposit amount in requests
        ticket = depositRequestsCount;
        depositRequests[ticket] = DepositRequest({depositor: msg.sender, assets: SafeCast.toUint96(assets)});

        unchecked {
            // cannot realistically overflow
            depositRequestsCount++;
        }

        emit DepositQueueEntered(msg.sender, ticket, assets);
    }

    /**
     * @dev Internal function for updating the minimum bond assets
     * @param newMinBondAssets The new minimum bond assets
     */
    function _setMinBondAssets(uint256 newMinBondAssets) private {
        if (newMinBondAssets == 0) revert Errors.InvalidAssets();
        minBondAssets = newMinBondAssets;
        emit MinBondAssetsUpdated(newMinBondAssets);
    }

    /**
     * @dev Internal function for updating the exit penalty percent
     * @param newExitPenaltyPercent The new exit penalty percent
     * @param isInitialization Flag indicating whether the penalty is set during initialization
     */
    function _setExitPenaltyPercent(uint16 newExitPenaltyPercent, bool isInitialization) private {
        if (newExitPenaltyPercent > _maxPenaltyPercent) revert Errors.InvalidFeePercent();

        if (!isInitialization) {
            if (_lastPenaltyUpdateTimestamp + _penaltyUpdateDelay > block.timestamp) {
                revert Errors.TooEarlyUpdate();
            }

            // check that the penalty percent can be increased only by 20% at a time
            // if the current penalty is 0, then it cannot exceed 1% initially
            uint256 currentPenaltyPercent = exitPenaltyPercent;
            uint256 maxAllowedPercent = currentPenaltyPercent > 0
                ? (currentPenaltyPercent * _penaltyUpdateMultiplier) / _penaltyUpdateBase
                : _penaltyUpdateBase;
            if (maxAllowedPercent < newExitPenaltyPercent) {
                revert Errors.InvalidFeePercent();
            }
        }

        exitPenaltyPercent = newExitPenaltyPercent;
        _lastPenaltyUpdateTimestamp = uint64(block.timestamp);
        emit ExitPenaltyPercentUpdated(msg.sender, newExitPenaltyPercent);
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @dev Transfers assets to the receiver. Must be implemented by network-specific contracts.
     * @param receiver The address to transfer assets to
     * @param assets The amount of assets to transfer
     */
    function _transferAssets(address receiver, uint256 assets) internal virtual;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
