// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

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
     * @notice Event emitted when the owner claims accumulated penalties
     * @param caller The address of the function caller
     * @param recipient The address that received the penalty assets
     * @param assets The amount of penalty assets claimed
     */
    event PenaltyClaimed(address indexed caller, address indexed recipient, uint256 assets);

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
     * @notice The exit penalty percent in BPS applied to processed deposit requests (10000 = 100%)
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
     * @notice The total number of deposit requests
     * @return The total number of deposit requests
     */
    function depositRequestsCount() external view returns (uint256);

    /**
     * @notice The number of processed deposit requests
     * @return The number of processed deposit requests
     */
    function processedDepositRequestsCount() external view returns (uint256);

    /**
     * @notice Returns the deposit request for the given ticket
     * @param ticket The deposit queue ticket
     * @return depositor The address of the depositor
     * @return assets The deposit assets
     */
    function depositRequests(uint256 ticket) external view returns (address depositor, uint96 assets);

    /**
     * @notice Exits the deposit queue and reclaims the deposit
     * @param ticket The deposit queue ticket to exit
     */
    function exitDepositQueue(uint256 ticket) external;
}
