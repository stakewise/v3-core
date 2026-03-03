// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IERC1822Proxiable} from "@openzeppelin/contracts/interfaces/draft-IERC1822.sol";
import {IERC5267} from "@openzeppelin/contracts/interfaces/IERC5267.sol";
import {IKeeperValidators} from "./IKeeperValidators.sol";
import {IKeeperRewards} from "./IKeeperRewards.sol";
import {IMulticall} from "./IMulticall.sol";

/**
 * @title INodesManager
 * @author StakeWise
 * @notice Defines the interface for the NodesManager contract
 */
interface INodesManager is IERC5267, IERC1822Proxiable, IMulticall {
    /**
     * @notice Event emitted on deposit
     * @param operator The address of the operator
     * @param assets The deposit assets before the penalty is applied if any
     * @param shares The deposit shares before the penalty is applied if any
     * @param penaltyAssets The amount of assets deducted as penalty
     * @param penaltyShares The amount of shares deducted as penalty
     */
    event Deposited(
        address indexed operator, uint256 assets, uint256 shares, uint256 penaltyAssets, uint256 penaltyShares
    );

    /**
     * @notice Event emitted on validators registration
     * @param operator The address of the operator
     * @param nonce The nonce used for signature replay protection
     * @param publicKeys The concatenation of the validators' public keys
     */
    event ValidatorsRegistered(address indexed operator, uint256 nonce, bytes publicKeys);

    /**
     * @notice Event emitted on validators funding
     * @param operator The address of the operator
     * @param nonce The nonce used for signature replay protection
     * @param publicKeys The concatenation of the validators' public keys
     */
    event ValidatorsFunded(address indexed operator, uint256 nonce, bytes publicKeys);

    /**
     * @notice Event emitted when the minimum deposit assets are updated
     * @param minDepositAssets The new minimum deposit assets
     */
    event MinDepositAssetsUpdated(uint256 minDepositAssets);

    /**
     * @notice Event emitted when the minimum balance percent is updated
     * @param caller The address of the function caller
     * @param minBalancePercent The new minimum balance percent
     */
    event MinBalancePercentUpdated(address indexed caller, uint16 minBalancePercent);

    /**
     * @notice Event emitted when the withdrawals manager is updated
     * @param withdrawalsManager The new withdrawals manager address
     */
    event WithdrawalsManagerUpdated(address withdrawalsManager);

    /**
     * @notice Event emitted on entering the exit queue
     * @param operator The address of the operator
     * @param positionTicket The exit queue ticket assigned to the position
     * @param shares The number of shares that queued for the exit
     */
    event ExitQueueEntered(address indexed operator, uint256 positionTicket, uint256 shares);

    /**
     * @notice Event emitted when shares are redeemed directly without entering the exit queue
     * @param operator The address of the operator
     * @param assets The amount of assets redeemed
     * @param shares The number of shares redeemed
     */
    event Redeemed(address indexed operator, uint256 assets, uint256 shares);

    /**
     * @notice Event emitted on claim of the exited assets
     * @param operator The address of the operator
     * @param prevPositionTicket The exit queue ticket received after the `enterExitQueue` call
     * @param newPositionTicket The new exit queue ticket in case not all the shares were exited. Otherwise 0.
     * @param withdrawnAssets The total number of assets withdrawn
     * @param penaltyAssets The amount of assets deducted as penalty
     */
    event ExitedAssetsClaimed(
        address indexed operator,
        uint256 prevPositionTicket,
        uint256 newPositionTicket,
        uint256 withdrawnAssets,
        uint256 penaltyAssets
    );

    /**
     * @notice Event emitted when a validator withdrawal is submitted
     * @param caller The address of the function caller
     */
    event ValidatorWithdrawalSubmitted(address indexed caller);

    /**
     * @notice Event emitted on state update
     * @param caller The address of the function caller
     * @param stateRoot The new state merkle tree root
     * @param updateTimestamp The update timestamp used for state calculation
     * @param nonce The nonce used for verifying signatures
     * @param stateIpfsHash The new state IPFS hash
     */
    event StateUpdated(
        address indexed caller, bytes32 indexed stateRoot, uint64 updateTimestamp, uint256 nonce, string stateIpfsHash
    );

    /**
     * @notice Event emitted when the operator state is updated
     * @param operator The address of the operator
     * @param totalAssets The new total assets of the operator
     * @param cumPenaltyAssets The new cumulative penalty assets
     * @param cumEarnedFeeShares The new cumulative earned fee shares
     */
    event OperatorStateUpdated(
        address indexed operator, uint128 totalAssets, uint128 cumPenaltyAssets, uint128 cumEarnedFeeShares
    );

    /**
     * @notice Event emitted when the validators manager is updated for an operator
     * @param operator The address of the operator
     * @param validatorsManager The new validators manager address
     */
    event ValidatorsManagerUpdated(address indexed operator, address indexed validatorsManager);

    /**
     * @notice Event emitted when the state update delay is updated
     * @param stateUpdateDelay The new state update delay in seconds
     */
    event StateUpdateDelayUpdated(uint256 stateUpdateDelay);

    /**
     * @notice The type of operator nonce
     * @param RegisterValidatorsSig The nonce key for register validators signatures
     * @param FundValidatorsSig The nonce key for fund validators signatures
     * @param LastStateUpdate The nonce key for the last state update nonce
     * @param LastValidatorChange The state nonce at the time of the last validator registration or funding
     */
    enum OperatorNonceType {
        RegisterValidatorsSig,
        FundValidatorsSig,
        LastStateUpdate,
        LastValidatorChange
    }

    /**
     * @notice A struct containing parameters for state update
     * @param stateRoot The new state merkle root
     * @param updateTimestamp The update timestamp used for state calculation
     * @param stateIpfsHash The new IPFS hash with the state data for the new root
     * @param signatures The concatenation of the Oracles' signatures
     */
    struct StateUpdateParams {
        bytes32 stateRoot;
        uint64 updateTimestamp;
        string stateIpfsHash;
        bytes signatures;
    }

    /**
     * @notice A struct containing parameters for updating operator state
     * @param totalAssets The current total assets of the operator in validators
     * @param cumPenaltyAssets The cumulative penalty assets applied to the operator
     * @param cumEarnedFeeShares The cumulative fee shares earned by the operator
     * @param proof The merkle proof of the operator's state in the state tree
     */
    struct OperatorStateUpdateParams {
        uint128 totalAssets;
        uint128 cumPenaltyAssets;
        uint128 cumEarnedFeeShares;
        bytes32[] proof;
    }

    /**
     * @notice A struct containing the operator's state in the nodes manager
     * @param totalAssets The operator's total active assets in validators
     * @param balanceShares The vault shares balance of the operator
     * @param cumPenaltyAssets The cumulative penalty assets applied to the operator
     * @param cumEarnedFeeShares The cumulative fee shares earned by the operator
     */
    struct OperatorState {
        uint128 totalAssets;
        uint128 balanceShares;
        uint128 cumPenaltyAssets;
        uint128 cumEarnedFeeShares;
    }

    /**
     * @notice A struct containing the state data of the nodes manager
     * @param root The latest merkle tree root of the state
     * @param updateDelay The delay in seconds between state updates
     * @param lastUpdateTimestamp The timestamp of the last state update
     * @param currentNonce The nonce used for updating state merkle tree root
     */
    struct StateData {
        bytes32 root;
        uint64 updateDelay;
        uint64 lastUpdateTimestamp;
        uint128 currentNonce;
    }

    /**
     * @notice The pending penalty assets that could not be applied due to insufficient balance
     * @param operator The operator address
     * @return penaltyAssets The pending penalty assets
     */
    function pendingPenaltyAssets(address operator) external view returns (uint256 penaltyAssets);

    /**
     * @notice The address of the vault the NodesManager is attached to
     * @return The vault address
     */
    function vault() external view returns (address);

    /**
     * @notice The nonce for the given operator and nonce type
     * @param operator The operator address
     * @param nonceType The type of nonce
     * @return The current nonce value
     */
    function operatorNonces(address operator, OperatorNonceType nonceType) external view returns (uint256);

    /**
     * @notice The state of the given operator
     * @param operator The operator address
     * @return totalAssets The total assets of the operator
     * @return balanceShares The vault shares balance
     * @return cumPenaltyAssets The cumulative penalty assets
     * @return cumEarnedFeeShares The cumulative earned fee shares
     */
    function operatorStates(address operator)
        external
        view
        returns (uint128 totalAssets, uint128 balanceShares, uint128 cumPenaltyAssets, uint128 cumEarnedFeeShares);

    /**
     * @notice The state data of the nodes manager
     * @return root The latest merkle tree root of the state
     * @return updateDelay The delay in seconds between state updates
     * @return lastUpdateTimestamp The timestamp of the last state update
     * @return currentNonce The nonce used for updating state merkle tree root
     */
    function stateData()
        external
        view
        returns (bytes32 root, uint64 updateDelay, uint64 lastUpdateTimestamp, uint128 currentNonce);

    /**
     * @notice The minimum assets required for a deposit request
     * @return The minimum deposit assets
     */
    function minDepositAssets() external view returns (uint256);

    /**
     * @notice Updates the minimum deposit assets. Can only be called by the owner.
     * @param newMinDepositAssets The new minimum deposit assets
     */
    function setMinDepositAssets(uint256 newMinDepositAssets) external;

    /**
     * @notice The minimum balance percent in BPS (10000 = 100%)
     * @return The minimum balance percent
     */
    function minBalancePercent() external view returns (uint16);

    /**
     * @notice Updates the minimum balance percent. Can only be called by the owner.
     * @param newMinBalancePercent The new minimum balance percent
     */
    function setMinBalancePercent(uint16 newMinBalancePercent) external;

    /**
     * @notice Updates the vault state by harvesting rewards
     * @param harvestParams The parameters for harvesting Keeper rewards
     */
    function updateVaultState(IKeeperRewards.HarvestParams calldata harvestParams) external;

    /**
     * @notice The address of the withdrawals manager
     * @return The withdrawals manager address
     */
    function withdrawalsManager() external view returns (address);

    /**
     * @notice Updates the withdrawals manager address. Can only be called by the owner.
     * @param newWithdrawalsManager The new withdrawals manager address
     */
    function setWithdrawalsManager(address newWithdrawalsManager) external;

    /**
     * @notice The validators manager address for the given operator
     * @param operator The operator address
     * @return The validators manager address
     */
    function validatorsManagers(address operator) external view returns (address);

    /**
     * @notice Sets the validators manager address for the calling operator
     * @param validatorsManager The new validators manager address
     */
    function setValidatorsManager(address validatorsManager) external;

    /**
     * @notice Registers validators with oracle-approved signatures. Can only be called by the operator's validators manager.
     * @param operator The address of the operator
     * @param keeperParams The keeper approval parameters containing validator data
     * @param signatures The concatenation of the oracles' signatures
     */
    function registerValidators(
        address operator,
        IKeeperValidators.ApprovalParams calldata keeperParams,
        bytes calldata signatures
    ) external;

    /**
     * @notice Funds validators with oracle-approved signatures. Can only be called by the operator's validators manager.
     * @param operator The address of the operator
     * @param validators The concatenation of the validators' data
     * @param signatures The concatenation of the oracles' signatures approving the funding
     */
    function fundValidators(address operator, bytes calldata validators, bytes calldata signatures) external;

    /**
     * @notice Enters the exit queue by locking operator shares in the vault's exit queue
     * @param shares The number of shares to lock in the exit queue
     * @return positionTicket The position ticket of the exit queue
     */
    function enterExitQueue(uint256 shares) external returns (uint256 positionTicket);

    /**
     * @notice Claims exited assets from the vault's exit queue for the operator
     * @param positionTicket The exit queue ticket received after the `enterExitQueue` call
     * @param timestamp The timestamp when the shares entered the exit queue
     * @param exitQueueIndex The exit queue index at which the shares were burned
     */
    function claimExitedAssets(uint256 positionTicket, uint256 timestamp, uint256 exitQueueIndex) external;

    /**
     * @notice Submits validator withdrawals. Can only be called by the withdrawals manager.
     * @param validators The concatenation of the validators' data
     */
    function withdrawValidators(bytes calldata validators) external payable;

    /**
     * @notice Updates the operator state by verifying a merkle proof against the current state root
     * @param operator The address of the operator to update
     * @param params The parameters for updating the operator state
     */
    function updateOperatorState(address operator, OperatorStateUpdateParams calldata params) external;

    /**
     * @notice Checks whether state can be updated
     * @return `true` if state can be updated, `false` otherwise
     */
    function canUpdateState() external view returns (bool);

    /**
     * @notice Update state data
     * @param params The struct containing state update parameters
     */
    function updateState(StateUpdateParams calldata params) external;

    /**
     * @notice Updates the state update delay. Can only be called by the owner.
     * @param newStateUpdateDelay The new state update delay in seconds
     */
    function setStateUpdateDelay(uint256 newStateUpdateDelay) external;
}
