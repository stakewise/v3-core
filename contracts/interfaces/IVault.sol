// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.16;

import {IERC20Permit} from './IERC20Permit.sol';

/**
 * @title IVault
 * @author StakeWise
 * @notice Defines the interface for the Vault contract
 */
interface IVault is IERC20Permit {
  /**
   * @notice Event emitted on deposit
   * @param caller The address that called the deposit function
   * @param owner The address that receives the shares
   * @param assets The number of assets deposited by the caller
   * @param shares The number of created shares
   */
  event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

  /**
   * @notice Event emitted on withdraw
   * @param caller The address that called the withdraw function
   * @param receiver The address that will receive withdrawn assets
   * @param owner The address that owns the shares
   * @param assets The total number of withdrawn assets
   * @param shares The total number of withdrawn shares
   */
  event Withdraw(
    address indexed caller,
    address indexed receiver,
    address indexed owner,
    uint256 assets,
    uint256 shares
  );

  /**
   * @notice Event emitted on shares added to the exit queue
   * @param caller The address that called the function
   * @param receiver The address that will receive withdrawn assets
   * @param owner The address that owns the shares
   * @param exitQueueId The exit queue ID that was assigned to the position
   * @param shares The number of shares that queued for the exit
   */
  event ExitQueueEnter(
    address indexed caller,
    address indexed receiver,
    address indexed owner,
    uint256 exitQueueId,
    uint256 shares
  );

  /**
   * @notice Event emitted on claim of the exited assets
   * @param caller The address that called the function
   * @param receiver The address that has received withdrawn assets
   * @param prevExitQueueId The exit queue ID received after the `enterExitQueue` call
   * @param newExitQueueId The new exit queue ID in case not all the shares were withdrawn. Otherwise 0.
   * @param withdrawnAssets The total number of assets withdrawn
   */
  event ExitedAssetsClaim(
    address indexed caller,
    address indexed receiver,
    uint256 indexed prevExitQueueId,
    uint256 newExitQueueId,
    uint256 withdrawnAssets
  );

  /**
   * @notice The contract that accumulates rewards received from priority fees and MEV
   * @return The contract address
   */
  function feesEscrow() external view returns (address);

  /**
   * @notice Queued Shares
   * @return The total number of shares queued for exit
   */
  function queuedShares() external view returns (uint128);

  /**
   * @notice Unclaimed Assets
   * @return The total number of assets that were withdrawn, but not claimed yet
   */
  function unclaimedAssets() external view returns (uint128);

  /**
   * @notice The exit queue update delay
   * @return The number of seconds that must pass between exit queue updates
   */
  function exitQueueUpdateDelay() external view returns (uint24);

  /**
   * @notice The last update of the exit queue
   * @return The timestamp of the exit queue last update
   */
  function exitQueueLastUpdate() external view returns (uint64);

  /**
   * @notice Total assets in the Vault
   * @return totalManagedAssets The total amount of the underlying asset that is “managed” by Vault
   */
  function totalAssets() external view returns (uint256 totalManagedAssets);

  /**
   * @notice Total assets available in the Vault. They can be staked or withdrawn.
   * @return The total amount of the underlying assets that are liquid in the Vault
   */
  function availableAssets() external view returns (uint256);

  /**
   * @notice Get the checkpoint index to claim exited assets from
   * @param exitQueueId The exit queue ID to get the checkpoint index for
   * @return The checkpoint index that should be used to claim exited assets.
   *         Returns -1 in case such index does not exist.
   */
  function getCheckpointIndex(uint256 exitQueueId) external view returns (int256);

  /**
   * @notice Converts shares to assets
   * @param assets The amount of assets to convert to shares
   * @return shares The amount of shares that the Vault would exchange for the amount of assets provided
   */
  function convertToShares(uint256 assets) external view returns (uint256 shares);

  /**
   * @notice Converts assets to shares
   * @param shares The amount of shares to convert to assets
   * @return assets The amount of assets that the Vault would exchange for the amount of shares provided
   */
  function convertToAssets(uint256 shares) external view returns (uint256 assets);

  /**
   * @notice Locks shares to the exit queue. The shares continue earning rewards until they will be burned.
   * @param shares The number of shares to lock
   * @param receiver The address that will receive assets upon withdrawal
   * @param owner The address that owns the shares
   * @return exitQueueId The exit queue ID that represents the shares position in the queue
   */
  function enterExitQueue(
    uint256 shares,
    address receiver,
    address owner
  ) external returns (uint256 exitQueueId);

  /**
   * @notice Claims assets that were withdrawn by going through the exit queue. It can be called only after the `enterExitQueue` call.
   * @param receiver The address that will receive assets. Must be the same as specified during the `enterExitQueue` function call.
   * @param exitQueueId The exit queue ID received after the `enterExitQueue` call
   * @param checkpointIndex The checkpoint index at which the shares were burned. It can be looked up by calling `getCheckpointIndex`.
   * @return newExitQueueId The new exit queue ID in case not all the shares were burned. Otherwise 0.
   * @return claimedAssets The number of assets claimed
   */
  function claimExitedAssets(
    address receiver,
    uint256 exitQueueId,
    uint256 checkpointIndex
  ) external returns (uint256 newExitQueueId, uint256 claimedAssets);

  /**
   * @notice Redeems assets from the Vault by utilising what has not been staked yet
   * @param shares The number of shares to burn
   * @param receiver The address that will receive assets
   * @param owner The address that owns the shares
   * @return assets The number of assets withdrawn
   */
  function redeem(
    uint256 shares,
    address receiver,
    address owner
  ) external returns (uint256 assets);

  /**
   * @notice Checks whether exit queue update can be called
   * @return `true` when `updateExitQueue` can be called, `false` otherwise
   */
  function canUpdateExitQueue() external view returns (bool);

  /**
   * @notice Updates exit queue by creating a checkpoint. Can be called only once per day.
   * The users whose turn is in the exit queue will be able to withdraw their assets.
   */
  function updateExitQueue() external;
}
