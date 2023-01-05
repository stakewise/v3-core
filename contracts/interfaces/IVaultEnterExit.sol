// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {IVaultImmutables} from './IVaultImmutables.sol';
import {IVaultToken} from './IVaultToken.sol';
import {IVaultState} from './IVaultState.sol';

/**
 * @title IVaultEnterExit
 * @author StakeWise
 * @notice Defines the interface for the VaultEnterExit contract
 */
interface IVaultEnterExit is IVaultImmutables, IVaultToken, IVaultState {
  // Custom errors
  error CapacityExceeded();
  error InvalidSharesAmount();
  error NotCollateralized();

  /**
   * @notice Event emitted on deposit
   * @param caller The address that called the deposit function
   * @param owner The address that received the shares
   * @param assets The number of assets deposited by the caller
   * @param shares The number of Vault tokens the owner received
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
  event ExitQueueEntered(
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
  event ExitedAssetsClaimed(
    address indexed caller,
    address indexed receiver,
    uint256 indexed prevExitQueueId,
    uint256 newExitQueueId,
    uint256 withdrawnAssets
  );

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
   * @notice Withdraws assets from the Vault by utilising what has not been staked yet
   * @param assets The number of assets to withdraw
   * @param receiver The address that will receive assets
   * @param owner The address that owns the shares
   * @return shares The number of shares burned
   */
  function withdraw(
    uint256 assets,
    address receiver,
    address owner
  ) external returns (uint256 shares);
}
