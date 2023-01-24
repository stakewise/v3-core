// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {IVaultState} from './IVaultState.sol';
import {IVaultToken} from './IVaultToken.sol';
import {IVaultValidators} from './IVaultValidators.sol';
import {IVaultEnterExit} from './IVaultEnterExit.sol';
import {IKeeperRewards} from './IKeeperRewards.sol';
import {IMevEscrow} from './IMevEscrow.sol';

/**
 * @title IVaultEthStaking
 * @author StakeWise
 * @notice Defines the interface for the VaultEthStaking contract
 */
interface IVaultEthStaking is IVaultToken, IVaultState, IVaultValidators, IVaultEnterExit {
  /**
   * @notice Security deposit amount
   * @return The amount that is permanently deposited by the Vault creator to protect from the inflation attack
   */
  function securityDeposit() external view returns (uint256);

  /**
   * @notice The contract that accumulates MEV rewards
   * @return The MEV escrow contract address
   */
  function mevEscrow() external view returns (IMevEscrow);

  /**
   * @notice Deposit ETH to the Vault
   * @param receiver The address that will receive Vault's shares
   * @return shares The number of shares minted
   */
  function deposit(address receiver) external payable returns (uint256 shares);

  /**
   * @notice Updates Vault state and deposits ETH to the Vault
   * @param receiver The address that will receive Vault's shares
   * @param harvestParams The parameters for harvesting Keeper rewards
   * @return shares The number of shares minted
   */
  function updateStateAndDeposit(
    address receiver,
    IKeeperRewards.HarvestParams calldata harvestParams
  ) external payable returns (uint256 shares);
}
