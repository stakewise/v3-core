// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IMulticall} from "./IMulticall.sol";
import {IKeeperRewards} from "./IKeeperRewards.sol";

/**
 * @title IRewardSplitter
 * @author StakeWise
 * @notice Defines the interface for the RewardSplitter contract
 */
interface IRewardSplitter is IMulticall {
    // Custom errors
    error NotHarvested();
    error InvalidAccount();
    error InvalidAmount();

    /**
     * @notice Structure for storing information about share holder
     * @param shares The amount of shares the account has
     * @param rewardPerShare The last synced reward per share
     */
    struct ShareHolder {
        uint128 shares;
        uint128 rewardPerShare;
    }

    /**
     * @notice Event emitted when the claim on behalf flag is updated
     * @param caller The address of the account that called the function
     * @param enabled The flag indicating whether the claim on behalf is enabled
     */
    event ClaimOnBehalfUpdated(address caller, bool enabled);

    /**
     * @notice Event emitted when the number of shares is increased for an account
     * @param account The address of the account for which the shares were increased
     * @param amount The amount of shares that were added
     */
    event SharesIncreased(address indexed account, uint256 amount);

    /**
     * @notice Event emitted when the number of shares is decreased for an account
     * @param account The address of the account for which the shares were decreased
     * @param amount The amount of shares that were deducted
     */
    event SharesDecreased(address indexed account, uint256 amount);

    /**
     * @notice Event emitted when the rewards are synced from the vault.
     * @param totalRewards The new total amount of rewards
     * @param rewardPerShare The new reward per share
     */
    event RewardsSynced(uint256 totalRewards, uint256 rewardPerShare);

    /**
     * @notice Event emitted when the rewards are withdrawn from the splitter
     * @param account The address of the account for which the rewards were withdrawn
     * @param amount The amount of rewards that were withdrawn
     */
    event RewardsWithdrawn(address indexed account, uint256 amount);

    /**
     * @notice Event emitted when the rewards are claimed on behalf
     * @param onBehalf The address of the account on behalf of which the rewards were claimed
     * @param positionTicket The position ticket in the exit queue
     * @param amount The amount of rewards that were claimed
     */
    event ExitQueueEnteredOnBehalf(address indexed onBehalf, uint256 positionTicket, uint256 amount);

    /**
     * @notice Event emitted when the exited assets are claimed on behalf
     * @param onBehalf The address of the account on behalf of which the assets were claimed
     * @param positionTicket The position ticket in the exit queue
     * @param amount The amount of assets that were claimed
     */
    event ExitedAssetsClaimedOnBehalf(address indexed onBehalf, uint256 positionTicket, uint256 amount);

    /**
     * @notice The vault to which the RewardSplitter is connected
     * @return The address of the vault
     */
    function vault() external view returns (address);

    /**
     * @notice The total number of shares in the splitter
     * @return The total number of shares
     */
    function totalShares() external view returns (uint256);

    /**
     * @notice Returns the address of shareholder on behalf of which the rewards are claimed
     * @param exitPosition The position in the exit queue
     * @return onBehalf The address of shareholder
     */
    function exitPositions(uint256 exitPosition) external view returns (address onBehalf);

    /**
     * @notice Returns whether the claim on behalf is enabled
     * @return `true` if the claim on behalf is enabled, `false` otherwise
     */
    function isClaimOnBehalfEnabled() external view returns (bool);

    /**
     * @notice The total amount of unclaimed rewards in the splitter
     * @return The total amount of rewards
     */
    function totalRewards() external view returns (uint128);

    /**
     * @notice Initializes the RewardSplitter contract
     * @param _vault The address of the vault to which the RewardSplitter will be connected
     */
    function initialize(address _vault) external;

    /**
     * @notice Sets the flag indicating whether the claim on behalf is enabled.
     * @param enabled The flag indicating whether the claim on behalf is enabled
     * Can only be called by the vault admin.
     */
    function setClaimOnBehalf(bool enabled) external;

    /**
     * @notice Retrieves the amount of splitter shares for the given account.
     *         The shares are used to calculate the amount of rewards the account is entitled to.
     * @param account The address of the account to get shares for
     */
    function sharesOf(address account) external view returns (uint256);

    /**
     * @notice Retrieves the amount of rewards the account is entitled to.
     *         The rewards are calculated based on the amount of shares the account has.
     *         Note, rewards must be synced using the `syncRewards` function.
     * @param account The address of the account to get rewards for
     */
    function rewardsOf(address account) external view returns (uint256);

    /**
     * @notice Checks whether new rewards can be synced from the vault.
     * @return True if new rewards can be synced, false otherwise
     */
    function canSyncRewards() external view returns (bool);

    /**
     * @notice Increases the amount of shares for the given account. Can only be called by the owner.
     * @param account The address of the account to increase shares for
     * @param amount The amount of shares to add
     */
    function increaseShares(address account, uint128 amount) external;

    /**
     * @notice Decreases the amount of shares for the given account. Can only be called by the owner.
     * @param account The address of the account to decrease shares for
     * @param amount The amount of shares to deduct
     */
    function decreaseShares(address account, uint128 amount) external;

    /**
     * @notice Updates the vault state. Can be used in multicall to update state, sync rewards and withdraw them.
     * @param harvestParams The harvest params to use for updating the vault state
     */
    function updateVaultState(IKeeperRewards.HarvestParams calldata harvestParams) external;

    /**
     * @notice Transfers the vault tokens to the given account. Can only be called for the vault with ERC-20 token.
     * @param rewards The amount of vault tokens to transfer
     * @param receiver The address of the account to transfer tokens to
     */
    function claimVaultTokens(uint256 rewards, address receiver) external;

    /**
     * @notice Sends the rewards to the exit queue
     * @param rewards The amount of rewards to send to the exit queue
     * @param receiver The address that will claim exited assets
     * @return positionTicket The position ticket of the exit queue
     */
    function enterExitQueue(uint256 rewards, address receiver) external returns (uint256 positionTicket);

    /**
     * @notice Enters the exit queue on behalf of the shareholder. Can only be called if claim on behalf is enabled.
     * @param rewards The amount of rewards to send to the exit queue
     * @param onBehalf The address of the account on behalf of which the rewards are sent to the exit queue
     * @return positionTicket The position ticket of the exit queue
     */
    function enterExitQueueOnBehalf(uint256 rewards, address onBehalf) external returns (uint256 positionTicket);

    /**
     * @notice Claims the exited assets from the vault.
     * @param positionTicket The position ticket in the exit queue
     * @param timestamp The timestamp when the shares entered the exit queue
     * @param exitQueueIndex The exit queue index of the exit request
     */
    function claimExitedAssetsOnBehalf(uint256 positionTicket, uint256 timestamp, uint256 exitQueueIndex) external;

    /**
     * @notice Syncs the rewards from the vault to the splitter. The vault state must be up-to-date.
     */
    function syncRewards() external;
}
