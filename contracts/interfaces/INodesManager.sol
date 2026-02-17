// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IKeeperValidators} from "./IKeeperValidators.sol";
import {IKeeperRewards} from "./IKeeperRewards.sol";

/**
 * @title INodesManager
 * @author StakeWise
 * @notice Defines the interface for the NodesManager contract
 */
interface INodesManager {
    /**
     * @notice Struct for storing deposit request data
     * @param depositor The address of the depositor
     * @param assets The deposit assets
     */
    struct DepositRequest {
        address depositor;
        uint96 assets;
    }

    /**
     * @notice Event emitted on entering the deposit queue
     * @param depositor The address of the depositor
     * @param ticket The deposit queue ticket assigned to the request
     * @param assets The deposit assets
     */
    event DepositQueueEntered(address indexed depositor, uint256 indexed ticket, uint256 assets);

    /**
     * @notice Event emitted on exiting the deposit queue
     * @param depositor The address of the depositor
     * @param ticket The deposit queue ticket that was exited
     * @param assets The assets returned to the depositor
     * @param penalty The penalty assets deducted
     */
    event DepositQueueExited(address indexed depositor, uint256 indexed ticket, uint256 assets, uint256 penalty);

    /**
     * @notice Event emitted on validators registration
     * @param depositor The address of the depositor
     * @param ticket The deposit queue ticket used for the bond
     * @param bondAssets The total bond assets deposited to the vault
     * @param shares The vault shares received for the bond
     */
    event ValidatorsRegistered(address indexed depositor, uint256 indexed ticket, uint256 bondAssets, uint256 shares);

    /**
     * @notice Event emitted on validators funding
     * @param depositor The address of the depositor
     * @param ticket The deposit queue ticket used for the bond
     * @param bondAssets The total bond assets deposited to the vault
     * @param shares The vault shares received for the bond
     */
    event ValidatorsFunded(address indexed depositor, uint256 indexed ticket, uint256 bondAssets, uint256 shares);

    /**
     * @notice Event emitted when the minimum bond assets are updated
     * @param minBondAssets The new minimum bond assets
     */
    event MinBondAssetsUpdated(uint256 minBondAssets);

    /**
     * @notice Event emitted when the exit penalty percent is updated
     * @param caller The address of the function caller
     * @param exitPenaltyPercent The new exit penalty percent
     */
    event ExitPenaltyPercentUpdated(address indexed caller, uint16 exitPenaltyPercent);

    /**
     * @notice Event emitted when the LTV percent is updated
     * @param caller The address of the function caller
     * @param ltvPercent The new LTV percent
     */
    event LtvPercentUpdated(address indexed caller, uint16 ltvPercent);

    /**
     * @notice Event emitted when the owner claims accumulated penalties
     * @param caller The address of the function caller
     * @param recipient The address that received the penalty assets
     * @param assets The amount of penalty assets claimed
     */
    event PenaltyClaimed(address indexed caller, address indexed recipient, uint256 assets);

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
     * @notice The address of the vault used for depositing bond assets
     * @return The vault address
     */
    function vault() external view returns (address);

    /**
     * @notice The minimum assets required for a deposit request
     * @return The minimum bond assets
     */
    function minBondAssets() external view returns (uint256);

    /**
     * @notice Updates the minimum bond assets. Can only be called by the owner.
     * @param newMinBondAssets The new minimum bond assets
     */
    function setMinBondAssets(uint256 newMinBondAssets) external;

    /**
     * @notice The exit penalty percent in BPS applied when exiting the deposit queue (10000 = 100%)
     * @return The exit penalty percent
     */
    function exitPenaltyPercent() external view returns (uint16);

    /**
     * @notice Updates the exit penalty percent. Can only be called by the owner.
     *         Subject to a 3-day delay and max 20% increase per update.
     * @param newExitPenaltyPercent The new exit penalty percent
     */
    function setExitPenaltyPercent(uint16 newExitPenaltyPercent) external;

    /**
     * @notice The LTV percent in BPS that determines the bond per validator (10000 = 100%)
     * @return The LTV percent
     */
    function ltvPercent() external view returns (uint16);

    /**
     * @notice Updates the LTV percent. Can only be called by the owner.
     * @param newLtvPercent The new LTV percent
     */
    function setLtvPercent(uint16 newLtvPercent) external;

    /**
     * @notice The total unclaimed penalty assets accumulated from exit penalties
     * @return The unclaimed penalty assets
     */
    function unclaimedPenalty() external view returns (uint256);

    /**
     * @notice Claims accumulated penalty assets. Can only be called by the owner.
     * @param recipient The address to receive the penalty assets
     */
    function claimPenalty(address recipient) external;

    /**
     * @notice The cumulative total number of tickets created
     * @return The cumulative total tickets
     */
    function totalTickets() external view returns (uint256);

    /**
     * @notice The latest processed ticket
     * @return The current ticket
     */
    function currentTicket() external view returns (uint256);

    /**
     * @notice Returns the deposit request for the given ticket
     * @param ticket The deposit queue ticket
     * @return depositor The address of the depositor
     * @return assets The deposit assets
     */
    function depositRequests(uint256 ticket) external view returns (address depositor, uint96 assets);

    /**
     * @notice Returns the vault shares balance for the given account
     * @param account The account address
     * @return The vault shares balance
     */
    function balances(address account) external view returns (uint256);

    /**
     * @notice Exits the deposit queue and reclaims the deposit
     * @param ticket The deposit queue ticket to exit
     */
    function exitDepositQueue(uint256 ticket) external;

    /**
     * @notice Registers validators using bond from the deposit queue
     * @param ticket The deposit queue ticket to use for the bond
     * @param keeperParams The keeper approval parameters containing validator data
     */
    function registerValidators(uint256 ticket, IKeeperValidators.ApprovalParams calldata keeperParams) external;

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
     * @notice Returns the current nonce for the given ticket, used for fund validators signature replay protection
     * @param ticket The deposit queue ticket
     * @return The current nonce
     */
    function ticketNonces(uint256 ticket) external view returns (uint256);

    /**
     * @notice Funds validators using bond from the deposit queue
     * @param ticket The deposit queue ticket to use for the bond
     * @param validators The concatenation of the validators' data
     * @param signatures The concatenation of the oracles' signatures approving the funding
     */
    function fundValidators(uint256 ticket, bytes calldata validators, bytes calldata signatures) external;

    /**
     * @notice Submits validator withdrawals. Can only be called by the withdrawals manager.
     * @param validators The concatenation of the validators' data
     */
    function withdrawValidators(bytes calldata validators) external payable;
}
