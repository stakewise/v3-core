// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IVaultState} from './IVaultState.sol';

/**
 * @title IVaultEnterExit
 * @author StakeWise
 * @notice Defines the interface for the VaultEnterExit contract
 */
interface IVaultEnterExit is IVaultState {
  /**
   * @notice Event emitted on deposit
   * @param caller The address that called the deposit function
   * @param receiver The address that received the shares
   * @param assets The number of assets deposited by the caller
   * @param shares The number of shares received
   * @param referrer The address of the referrer
   */
  event Deposited(
    address indexed caller,
    address indexed receiver,
    uint256 assets,
    uint256 shares,
    address referrer
  );

  /**
   * @notice Event emitted on redeem (deprecated)
   * @param owner The address that owns the shares
   * @param receiver The address that received withdrawn assets
   * @param assets The total number of withdrawn assets
   * @param shares The total number of withdrawn shares
   */
  event Redeemed(address indexed owner, address indexed receiver, uint256 assets, uint256 shares);

  /**
   * @notice Event emitted on shares added to the V1 exit queue (deprecated)
   * @param owner The address that owns the shares
   * @param receiver The address that will receive withdrawn assets
   * @param positionTicket The exit queue ticket that was assigned to the position
   * @param shares The number of shares that queued for the exit
   */
  event ExitQueueEntered(
    address indexed owner,
    address indexed receiver,
    uint256 positionTicket,
    uint256 shares
  );

  /**
   * @notice Event emitted on shares added to the V2 exit queue
   * @param owner The address that owns the shares
   * @param receiver The address that will receive withdrawn assets
   * @param positionTicket The exit queue ticket that was assigned to the position
   * @param shares The number of shares that queued for the exit
   * @param assets The number of assets that queued for the exit
   */
  event V2ExitQueueEntered(
    address indexed owner,
    address indexed receiver,
    uint256 positionTicket,
    uint256 shares,
    uint256 assets
  );

  /**
   * @notice Event emitted on claim of the exited assets
   * @param receiver The address that has received withdrawn assets
   * @param prevPositionTicket The exit queue ticket received after the `enterExitQueue` call
   * @param newPositionTicket The new exit queue ticket in case not all the assets were withdrawn. Otherwise 0.
   * @param withdrawnAssets The total number of assets withdrawn
   */
  event ExitedAssetsClaimed(
    address indexed receiver,
    uint256 prevPositionTicket,
    uint256 newPositionTicket,
    uint256 withdrawnAssets
  );

  /**
   * @notice Event emitted on relayer update
   * @param owner The address of the owner
   * @param relayer The address of the relayer
   */
  event RelayerUpdated(address owner, address relayer);

  /**
   * @notice Get the relayer address for the owner
   * @param owner The address of the owner
   * @return relayer The address of the relayer
   */
  function relayers(address owner) external view returns (address relayer);

  /**
   * @notice Set the relayer address for the caller
   * @param relayer The address of the relayer
   */
  function setRelayer(address relayer) external;

  /**
   * @notice Locks assets to the exit queue. The shares to assets rate will be locked at the moment of the call.
   * @param shares The number of shares to exit
   * @param receiver The address that will receive assets upon withdrawal
   * @return positionTicket The position ticket of the exit queue
   */
  function enterExitQueue(
    uint256 shares,
    address receiver
  ) external returns (uint256 positionTicket);

  /**
   * @notice Locks assets to the exit queue. The shares to assets rate will be locked at the moment of the call. The caller must be approved by the owner.
   * @param owner The address that owns the shares
   * @param shares The number of shares to exit
   * @param receiver The address that will receive assets upon withdrawal
   * @return positionTicket The position ticket of the exit queue
   */
  function enterExitQueueFromRelayer(
    address owner,
    uint256 shares,
    address receiver
  ) external returns (uint256 positionTicket);

  /**
   * @notice Get the exit queue index to claim exited assets from (deprecated)
   * @param positionTicket The exit queue position ticket to get the index for
   * @return The exit queue index that should be used to claim exited assets.
   *         Returns -1 in case such index does not exist.
   */
  function getExitQueueIndex(uint256 positionTicket) external view returns (int256);

  /**
   * @notice Calculates the number of assets that can be claimed from the exit queue.
   * @param receiver The address that will receive assets upon withdrawal
   * @param positionTicket The exit queue ticket received after the `enterExitQueue` call
   * @param timestamp The timestamp when the assets entered the exit queue
   * @param exitQueueIndex The exit queue index at which the shares were burned.
   *        It can be looked up by calling `getExitQueueIndex`. Only relevant for V1 positions, otherwise pass 0.
   * @return leftTickets The number of tickets left in the queue
   * @return exitedTickets The number of tickets that have already exited
   * @return exitedAssets The number of assets that can be claimed
   */
  function calculateExitedAssets(
    address receiver,
    uint256 positionTicket,
    uint256 timestamp,
    uint256 exitQueueIndex
  ) external view returns (uint256 leftTickets, uint256 exitedTickets, uint256 exitedAssets);

  /**
   * @notice Claims assets that were withdrawn by the Vault. It can be called only after the `enterExitQueue` call by the `receiver`.
   * @param positionTicket The exit queue ticket received after the `enterExitQueue` call
   * @param timestamp The timestamp when the assets entered the exit queue
   * @param exitQueueIndex The exit queue index at which the shares were burned.
   *        It can be looked up by calling `getExitQueueIndex`. Only relevant for V1 positions, otherwise pass 0.
   */
  function claimExitedAssets(
    uint256 positionTicket,
    uint256 timestamp,
    uint256 exitQueueIndex
  ) external;
}
