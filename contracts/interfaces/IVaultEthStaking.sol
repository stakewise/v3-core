// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {IVaultState} from './IVaultState.sol';
import {IVaultToken} from './IVaultToken.sol';
import {IVaultValidators} from './IVaultValidators.sol';
import {IVaultEnterExit} from './IVaultEnterExit.sol';
import {IKeeperRewards} from './IKeeperRewards.sol';
import {IVaultMev} from './IVaultMev.sol';

/**
 * @title IVaultEthStaking
 * @author StakeWise
 * @notice Defines the interface for the VaultEthStaking contract
 */
interface IVaultEthStaking is
  IVaultToken,
  IVaultState,
  IVaultValidators,
  IVaultEnterExit,
  IVaultMev
{
  /**
   * @notice Security deposit amount
   * @return The amount that is permanently deposited by the Vault creator to protect from the inflation attack
   */
  function securityDeposit() external view returns (uint256);

  /**
   * @notice Deposit ETH to the Vault
   * @param receiver The address that will receive Vault's shares
   * @param referrer The address of the referrer. Set to zero address if not used.
   * @return shares The number of shares minted
   */
  function deposit(address receiver, address referrer) external payable returns (uint256 shares);

  /**
   * @notice Used by MEV escrow to transfer ETH.
   */
  function receiveFromMevEscrow() external payable;

  /**
   * @notice Updates Vault state and deposits ETH to the Vault
   * @param receiver The address that will receive Vault's shares
   * @param referrer The address of the referrer. Set to zero address if not used.
   * @param harvestParams The parameters for harvesting Keeper rewards
   * @return shares The number of shares minted
   */
  function updateStateAndDeposit(
    address receiver,
    address referrer,
    IKeeperRewards.HarvestParams calldata harvestParams
  ) external payable returns (uint256 shares);
}
