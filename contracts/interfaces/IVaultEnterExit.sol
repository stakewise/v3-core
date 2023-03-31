// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

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
   * @param referrer The address of the referrer
   */
  event Deposit(
    address indexed caller,
    address indexed owner,
    uint256 assets,
    uint256 shares,
    address referrer
  );

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
   * @param positionCounter The exit queue counter that was assigned to the position
   * @param shares The number of shares that queued for the exit
   */
  event ExitQueueEntered(
    address indexed caller,
    address indexed receiver,
    address indexed owner,
    uint256 positionCounter,
    uint256 shares
  );

  /**
   * @notice Event emitted on claim of the exited assets
   * @param caller The address that called the function
   * @param receiver The address that has received withdrawn assets
   * @param prevPositionCounter The exit queue counter received after the `enterExitQueue` call
   * @param newPositionCounter The new exit queue counter in case not all the shares were withdrawn. Otherwise 0.
   * @param withdrawnAssets The total number of assets withdrawn
   */
  event ExitedAssetsClaimed(
    address indexed caller,
    address indexed receiver,
    uint256 prevPositionCounter,
    uint256 newPositionCounter,
    uint256 withdrawnAssets
  );

  /**
   * @notice Locks shares to the exit queue. The shares continue earning rewards until they will be burned by the Vault.
   * @param shares The number of shares to lock
   * @param receiver The address that will receive assets upon withdrawal
   * @param owner The address that owns the shares
   * @return positionCounter The exit queue counter assigned to the position
   */
  function enterExitQueue(
    uint256 shares,
    address receiver,
    address owner
  ) external returns (uint256 positionCounter);

  /**
   * @notice Claims assets that were withdrawn by the Vault. It can be called only after the `enterExitQueue` call.
   * @param receiver The address that will receive assets. Must be the same as specified during the `enterExitQueue` function call.
   * @param positionCounter The exit queue counter received after the `enterExitQueue` call
   * @param checkpointIndex The checkpoint index at which the shares were burned. It can be looked up by calling `getCheckpointIndex`.
   * @return newPositionCounter The new exit queue counter in case not all the shares were burned. Otherwise 0.
   * @return claimedShares The number of shares claimed
   * @return claimedAssets The number of assets claimed
   */
  function claimExitedAssets(
    address receiver,
    uint256 positionCounter,
    uint256 checkpointIndex
  ) external returns (uint256 newPositionCounter, uint256 claimedShares, uint256 claimedAssets);

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
