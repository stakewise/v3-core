// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {INodesManager} from "../interfaces/INodesManager.sol";
import {IKeeperValidators} from "../interfaces/IKeeperValidators.sol";
import {IKeeperRewards} from "../interfaces/IKeeperRewards.sol";
import {IVaultState} from "../interfaces/IVaultState.sol";
import {IVaultValidators} from "../interfaces/IVaultValidators.sol";
import {Errors} from "../libraries/Errors.sol";
import {Multicall} from "../base/Multicall.sol";
import {ValidatorUtils} from "../libraries/ValidatorUtils.sol";

abstract contract NodesManager is Ownable2StepUpgradeable, UUPSUpgradeable, Multicall, INodesManager {
    uint256 internal constant _maxPercent = 10_000; // @dev 100.00 %
    uint256 private constant _penaltyUpdateDelay = 3 days;
    uint256 private constant _penaltyUpdateMultiplier = 120;
    uint256 private constant _penaltyUpdateBase = 100;
    uint256 private constant _validatorV2DepositLength = 184;

    /// @inheritdoc INodesManager
    address public immutable override vault;

    /// @inheritdoc INodesManager
    uint256 public override minBondAssets;

    /// @inheritdoc INodesManager
    uint16 public override exitPenaltyPercent;

    uint64 private _lastPenaltyUpdateTimestamp;

    /// @inheritdoc INodesManager
    uint256 public override unclaimedPenalty;

    /// @inheritdoc INodesManager
    uint256 public override totalTickets;

    /// @inheritdoc INodesManager
    uint256 public override currentTicket;

    /// @inheritdoc INodesManager
    mapping(uint256 ticket => DepositRequest request) public override depositRequests;

    /// @inheritdoc INodesManager
    uint16 public override ltvPercent;

    /// @inheritdoc INodesManager
    mapping(address account => uint256 shares) public override balances;

    /**
     * @dev Constructor sets the vault immutable
     * @param _vault The address of the vault for depositing bond assets
     */
    constructor(address _vault) {
        vault = _vault;
    }

    /**
     * @dev Initializes the NodesManager contract
     * @param _owner The address of the contract owner
     * @param _minBondAssets The minimum assets required for a deposit request
     * @param _exitPenaltyPercent The exit penalty percent in BPS
     * @param _ltvPercent The LTV percent in BPS
     */
    function __NodesManager_init(address _owner, uint256 _minBondAssets, uint16 _exitPenaltyPercent, uint16 _ltvPercent)
        internal
        onlyInitializing
    {
        __Ownable_init(_owner);
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        _setMinBondAssets(_minBondAssets);
        _setExitPenaltyPercent(_exitPenaltyPercent, true);
        _setLtvPercent(_ltvPercent);
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
    function setLtvPercent(uint16 newLtvPercent) external override onlyOwner {
        if (ltvPercent == newLtvPercent) revert Errors.ValueNotChanged();
        _setLtvPercent(newLtvPercent);
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
    function updateVaultState(IKeeperRewards.HarvestParams calldata harvestParams) external override {
        IVaultState(vault).updateState(harvestParams);
    }

    /// @inheritdoc INodesManager
    function exitDepositQueue(uint256 ticket) external override {
        DepositRequest memory request = depositRequests[ticket];
        if (request.depositor != msg.sender) revert Errors.AccessDenied();

        uint256 assets = request.assets;
        if (assets == 0) revert Errors.InvalidAssets();

        uint256 penalty = Math.mulDiv(assets, exitPenaltyPercent, _maxPercent);
        if (penalty > 0) {
            unchecked {
                // cannot underflow as penalty is guaranteed to be less than assets
                assets -= penalty;
                // cannot realistically overflow as penalty is expected to be a small percentage of assets
                unclaimedPenalty += penalty;
            }
        }

        delete depositRequests[ticket];
        _transferAssets(msg.sender, assets);
        emit DepositQueueExited(msg.sender, ticket, assets, penalty);
    }

    /// @inheritdoc INodesManager
    function registerValidators(uint256 ticket, IKeeperValidators.ApprovalParams calldata keeperParams)
        external
        override
    {
        // check whether the caller has deposit request based on ticket and msg.sender
        DepositRequest memory request = depositRequests[ticket];
        if (request.depositor != msg.sender) revert Errors.AccessDenied();

        (uint256 validatorsCount, uint256 totalDeposit) = _getValidatorsTotalDeposit(keeperParams.validators);
        if (totalDeposit == 0) revert Errors.InvalidValidators();

        // calculate required bond based on the total deposit and ltvPercent
        uint256 totalBond = Math.mulDiv(totalDeposit, _maxPercent - ltvPercent, _maxPercent);
        if (totalBond == 0) revert Errors.InvalidLtvPercent();
        if (request.assets < totalBond) revert Errors.InvalidAssets();

        // deposit bond to the vault and update balance
        uint256 shares = _depositToVault(totalBond);
        balances[msg.sender] += shares;

        // register validators in the vault
        IVaultValidators(vault).registerValidators(keeperParams, bytes(""));

        // update state
        if (ticket > currentTicket) {
            currentTicket = ticket;
        }

        uint256 remainingAssets;
        unchecked {
            // cannot underflow as request.assets >= totalBond is checked above
            remainingAssets = request.assets - totalBond;
        }

        if (remainingAssets < minBondAssets) {
            delete depositRequests[ticket];
            if (remainingAssets > 0) {
                _transferAssets(msg.sender, remainingAssets);
            }
        } else {
            depositRequests[ticket].assets = SafeCast.toUint96(remainingAssets);
        }

        // emit event
        emit ValidatorsRegistered(msg.sender, ticket, validatorsCount, totalBond, shares);
    }

    /**
     * @dev Enters the deposit queue with the given assets
     * @param assets The amount of assets to deposit
     * @return ticket The deposit queue ticket assigned to the request
     */
    function _enterDepositQueue(uint256 assets) internal returns (uint256 ticket) {
        if (assets < minBondAssets) revert Errors.InvalidAssets();

        // store the sender address and the deposit amount in requests
        ticket = totalTickets;
        depositRequests[ticket] = DepositRequest({depositor: msg.sender, assets: SafeCast.toUint96(assets)});

        unchecked {
            // cannot realistically overflow
            totalTickets++;
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
        if (newExitPenaltyPercent > _maxPercent) revert Errors.InvalidFeePercent();

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

    /**
     * @dev Internal function for updating the LTV percent
     * @param newLtvPercent The new LTV percent
     */
    function _setLtvPercent(uint16 newLtvPercent) private {
        if (newLtvPercent == 0 || newLtvPercent >= _maxPercent) revert Errors.InvalidLtvPercent();
        ltvPercent = newLtvPercent;
        emit LtvPercentUpdated(msg.sender, newLtvPercent);
    }

    /**
     * @dev Internal function to calculate the total deposit amount from the validators data
     * @param validators The concatenation of the validators' data
     * @return validatorsCount The number of validators
     * @return totalDeposit The total deposit amount calculated from the validators data
     */
    function _getValidatorsTotalDeposit(bytes calldata validators)
        internal
        pure
        returns (uint256 validatorsCount, uint256 totalDeposit)
    {
        uint256 validatorsLength = validators.length;
        if (validatorsLength == 0 || validatorsLength % _validatorV2DepositLength != 0) {
            revert Errors.InvalidValidators();
        }
        validatorsCount = validatorsLength / _validatorV2DepositLength;

        // calculate total deposit by summing up the deposits of all validators
        uint256 startIndex;
        for (uint256 i = 0; i < validatorsCount;) {
            totalDeposit += ValidatorUtils.getValidatorDepositAmount(
                validators[startIndex:startIndex + _validatorV2DepositLength]
            );
            unchecked {
                ++i;
                startIndex += _validatorV2DepositLength;
            }
        }
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
     * @dev Deposits assets to the vault and returns the shares received.
     *      Must be implemented by network-specific contracts.
     * @param assets The amount of assets to deposit
     * @return shares The vault shares received
     */
    function _depositToVault(uint256 assets) internal virtual returns (uint256 shares);

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
