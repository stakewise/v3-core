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
     * @param assets The deposit assets
     * @param shares The vault shares received for the deposit
     */
    event Deposited(address indexed operator, uint256 assets, uint256 shares);

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
     * @notice Event emitted when the LTV percent is updated
     * @param caller The address of the function caller
     * @param ltvPercent The new LTV percent
     */
    event LtvPercentUpdated(address indexed caller, uint16 ltvPercent);

    /**
     * @notice Event emitted when the withdrawals manager is updated
     * @param withdrawalsManager The new withdrawals manager address
     */
    event WithdrawalsManagerUpdated(address withdrawalsManager);

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
     * @notice Event emitted when the state update delay is updated
     * @param stateUpdateDelay The new state update delay in seconds
     */
    event StateUpdateDelayUpdated(uint256 stateUpdateDelay);

    /**
     * @notice The type of operator nonce
     * @param RegisterValidatorsSig The nonce key for register validators signatures
     * @param FundValidatorsSig The nonce key for fund validators signatures
     * @param LastStateUpdate The nonce key for the last state update nonce
     */
    enum OperatorNonceType {
        RegisterValidatorsSig,
        FundValidatorsSig,
        LastStateUpdate
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
     * @notice The LTV percent in BPS that determines the assets per validator (10000 = 100%)
     * @return The LTV percent
     */
    function ltvPercent() external view returns (uint16);

    /**
     * @notice Updates the LTV percent. Can only be called by the owner.
     * @param newLtvPercent The new LTV percent
     */
    function setLtvPercent(uint16 newLtvPercent) external;

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
     * @notice Registers validators with oracle-approved signatures
     * @param keeperParams The keeper approval parameters containing validator data
     * @param signatures The concatenation of the oracles' signatures
     */
    function registerValidators(IKeeperValidators.ApprovalParams calldata keeperParams, bytes calldata signatures)
        external;

    /**
     * @notice Funds validators with oracle-approved signatures
     * @param validators The concatenation of the validators' data
     * @param signatures The concatenation of the oracles' signatures approving the funding
     */
    function fundValidators(bytes calldata validators, bytes calldata signatures) external;

    /**
     * @notice Submits validator withdrawals. Can only be called by the withdrawals manager.
     * @param validators The concatenation of the validators' data
     */
    function withdrawValidators(bytes calldata validators) external payable;

    /**
     * @notice Updates the operator state by verifying a merkle proof against the current state root
     * @param params The parameters for updating the operator state
     */
    function updateOperatorState(OperatorStateUpdateParams calldata params) external;

    /**
     * @notice Returns the operator's current shares and assets after applying pending penalties and earned fees
     * @param operator The operator address
     * @param cumPenaltyAssets The cumulative penalty assets to apply
     * @param cumEarnedFeeShares The cumulative earned fee shares to apply
     * @return shares The operator's vault shares balance after adjustments
     * @return assets The operator's assets value after adjustments
     * @return vaultHarvested Whether the vault has been harvested
     */
    function getOperatorBalance(address operator, uint128 cumPenaltyAssets, uint128 cumEarnedFeeShares)
        external
        view
        returns (uint256 shares, uint256 assets, bool vaultHarvested);

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
