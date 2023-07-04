// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

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
   * @notice Event emitted on redeem
   * @param owner The address that owns the shares
   * @param receiver The address that received withdrawn assets
   * @param assets The total number of withdrawn assets
   * @param shares The total number of withdrawn shares
   */
  event Redeemed(address indexed owner, address indexed receiver, uint256 assets, uint256 shares);

  /**
   * @notice Event emitted on shares added to the exit queue
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
   * @notice Event emitted on claim of the exited assets
   * @param receiver The address that has received withdrawn assets
   * @param prevPositionTicket The exit queue ticket received after the `enterExitQueue` call
   * @param newPositionTicket The new exit queue ticket in case not all the shares were withdrawn. Otherwise 0.
   * @param withdrawnAssets The total number of assets withdrawn
   */
  event ExitedAssetsClaimed(
    address indexed receiver,
    uint256 prevPositionTicket,
    uint256 newPositionTicket,
    uint256 withdrawnAssets
  );

  /**
   * @notice Locks shares to the exit queue. The shares continue earning rewards until they will be burned by the Vault.
   * @param shares The number of shares to lock
   * @param receiver The address that will receive assets upon withdrawal
   * @return positionTicket The exit queue ticket assigned to the position
   */
  function enterExitQueue(
    uint256 shares,
    address receiver
  ) external returns (uint256 positionTicket);

  /**
   * @notice Get the exit queue index to claim exited assets from
   * @param positionTicket The exit queue position ticket to get the index for
   * @return The exit queue index that should be used to claim exited assets.
   *         Returns -1 in case such index does not exist.
   */
  function getExitQueueIndex(uint256 positionTicket) external view returns (int256);

  /**
   * @notice Claims assets that were withdrawn by the Vault. It can be called only after the `enterExitQueue` call by the `receiver`.
   * @param positionTicket The exit queue ticket received after the `enterExitQueue` call
   * @param exitQueueIndex The exit queue index at which the shares were burned. It can be looked up by calling `getExitQueueIndex`.
   * @return newPositionTicket The new exit queue ticket in case not all the shares were burned. Otherwise 0.
   * @return claimedShares The number of shares claimed
   * @return claimedAssets The number of assets claimed
   */
  function claimExitedAssets(
    uint256 positionTicket,
    uint256 exitQueueIndex
  ) external returns (uint256 newPositionTicket, uint256 claimedShares, uint256 claimedAssets);

  /**
   * @notice Redeems assets from the Vault by utilising what has not been staked yet
   * @param shares The number of shares to burn
   * @param receiver The address that will receive assets
   * @return assets The number of assets withdrawn
   */
  function redeem(uint256 shares, address receiver) external returns (uint256 assets);
}
