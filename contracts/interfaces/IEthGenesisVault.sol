// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {IEthVault} from './IEthVault.sol';

/**
 * @title IEthGenesisVault
 * @author StakeWise
 * @notice Defines the interface for the EthGenesisVault contract
 */
interface IEthGenesisVault is IEthVault {
  /**
   * @notice Event emitted on migration from StakeWise v2
   * @param receiver The address of the shares receiver
   * @param assets The amount of assets migrated
   * @param shares The amount of shares migrated
   */
  event Migrated(address receiver, uint256 assets, uint256 shares);

  /**
   * @notice Function for migrating from StakeWise v2. Can be called only by RewardEthToken contract.
   * @param receiver The address of the receiver
   * @param assets The amount of assets migrated
   * @return shares The amount of shares minted
   */
  function migrate(address receiver, uint256 assets) external returns (uint256 shares);

  /**
   * @notice Function for accepting PoolEscrow contract ownership. Can only be called once by the admin.
   */
  function acceptPoolEscrowOwnership() external;
}
