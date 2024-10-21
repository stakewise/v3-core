// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IGnoVault} from './IGnoVault.sol';

/**
 * @title IGnoGenesisVault
 * @author StakeWise
 * @notice Defines the interface for the GnoGenesisVault contract
 */
interface IGnoGenesisVault is IGnoVault {
  /**
   * @notice Event emitted on migration from StakeWise Legacy
   * @param receiver The address of the shares receiver
   * @param assets The amount of assets migrated
   * @param shares The amount of shares migrated
   */
  event Migrated(address receiver, uint256 assets, uint256 shares);

  /**
   * @notice Event emitted on GnoGenesisVault creation
   * @param admin The address of the Vault admin
   * @param capacity The capacity of the Vault
   * @param feePercent The fee percent of the Vault
   * @param metadataIpfsHash The IPFS hash of the Vault metadata
   */
  event GenesisVaultCreated(
    address admin,
    uint256 capacity,
    uint16 feePercent,
    string metadataIpfsHash
  );

  /**
   * @notice Function for migrating from StakeWise Legacy. Can be called only by RewardGnoToken contract.
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
