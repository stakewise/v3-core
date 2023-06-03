// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {IVaultToken} from './IVaultToken.sol';
import {IVaultState} from './IVaultState.sol';

/**
 * @title IVaultEnterExit
 * @author StakeWise
 * @notice Defines the interface for the VaultEnterExit contract
 */
interface IVaultEnterExit is IVaultToken, IVaultState {
  // Custom errors
  error CapacityExceeded();
  error InvalidSharesAmount();
  error InvalidAssets();
  error InvalidShares();

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
   * @notice Event emitted on redeem
   * @param caller The address that called the function
   * @param receiver The address that received withdrawn assets
   * @param owner The address that owns the shares
   * @param assets The total number of withdrawn assets
   * @param shares The total number of withdrawn shares
   */
  event Redeem(
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
   * @param positionTicket The exit queue ticket that was assigned to the position
   * @param shares The number of shares that queued for the exit
   */
  event ExitQueueEntered(
    address indexed caller,
    address indexed receiver,
    address indexed owner,
    uint256 positionTicket,
    uint256 shares
  );

  /**
   * @notice Event emitted on claim of the exited assets
   * @param caller The address that called the function
   * @param receiver The address that has received withdrawn assets
   * @param prevPositionTicket The exit queue ticket received after the `enterExitQueue` call
   * @param newPositionTicket The new exit queue ticket in case not all the shares were withdrawn. Otherwise 0.
   * @param withdrawnAssets The total number of assets withdrawn
   */
  event ExitedAssetsClaimed(
    address indexed caller,
    address indexed receiver,
    uint256 prevPositionTicket,
    uint256 newPositionTicket,
    uint256 withdrawnAssets
  );

  /**
   * @notice Locks shares to the exit queue. The shares continue earning rewards until they will be burned by the Vault.
   * @param shares The number of shares to lock
   * @param receiver The address that will receive assets upon withdrawal
   * @param owner The address that owns the shares
   * @return positionTicket The exit queue ticket assigned to the position
   */
  function enterExitQueue(
    uint256 shares,
    address receiver,
    address owner
  ) external returns (uint256 positionTicket);

  /**
   * @notice Get the exit queue index to claim exited assets from
   * @param positionTicket The exit queue position ticket to get the index for
   * @return The exit queue index that should be used to claim exited assets.
   *         Returns -1 in case such index does not exist.
   */
  function getExitQueueIndex(uint256 positionTicket) external view returns (int256);

  /**
   * @notice Claims assets that were withdrawn by the Vault. It can be called only after the `enterExitQueue` call.
   * @param receiver The address that will receive assets. Must be the same as specified during the `enterExitQueue` function call.
   * @param positionTicket The exit queue ticket received after the `enterExitQueue` call
   * @param exitQueueIndex The exit queue index at which the shares were burned. It can be looked up by calling `getExitQueueIndex`.
   * @return newPositionTicket The new exit queue ticket in case not all the shares were burned. Otherwise 0.
   * @return claimedShares The number of shares claimed
   * @return claimedAssets The number of assets claimed
   */
  function claimExitedAssets(
    address receiver,
    uint256 positionTicket,
    uint256 exitQueueIndex
  ) external returns (uint256 newPositionTicket, uint256 claimedShares, uint256 claimedAssets);

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
}
