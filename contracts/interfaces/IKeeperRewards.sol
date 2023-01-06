// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {IOracles} from './IOracles.sol';
import {IRegistry} from './IRegistry.sol';

/**
 * @title IKeeperRewards
 * @author StakeWise
 * @notice Defines the interface for the Keeper contract rewards
 */
interface IKeeperRewards {
  // Custom errors
  error InvalidRewardsRoot();
  error InvalidProof();
  error AccessDenied();

  /**
   * @notice Event emitted on rewards root update
   * @param caller The address of the function caller
   * @param rewardsRoot The new rewards merkle tree root
   * @param updateTimestamp The update timestamp used for rewards calculation
   * @param nonce The nonce used for verifying signatures
   * @param rewardsIpfsHash The new rewards IPFS hash
   */
  event RewardsRootUpdated(
    address indexed caller,
    bytes32 indexed rewardsRoot,
    uint64 updateTimestamp,
    uint96 nonce,
    string rewardsIpfsHash
  );

  /**
   * @notice Event emitted on Vault harvest
   * @param vault The address of the Vault
   * @param rewardsRoot The rewards merkle tree root
   * @param reward The cumulative reward/penalty accumulated by the Vault
   */
  event Harvested(address indexed vault, bytes32 indexed rewardsRoot, int160 reward);

  /**
   * @notice A struct containing the last synced Vault's reward
   * @param nonce The nonce of the last synced reward
   * @param reward The last synced reward. Can be negative in case of penalty.
   */
  struct RewardSync {
    uint96 nonce;
    int160 reward;
  }

  /**
   * @notice A struct containing parameters for rewards merkle tree root update
   * @param rewardsRoot The new rewards merkle root
   * @param updateTimestamp The update timestamp used for rewards calculation
   * @param rewardsIpfsHash The new IPFS hash with all the Vaults' rewards for the new root
   * @param signatures The concatenation of the Oracles' signatures
   */
  struct RewardsRootUpdateParams {
    bytes32 rewardsRoot;
    uint64 updateTimestamp;
    string rewardsIpfsHash;
    bytes signatures;
  }

  /**
   * @notice A struct containing parameters for harvesting rewards. Can only be called by Vault.
   * @param rewardsRoot The rewards merkle root
   * @param vaultReward The Vault cumulative reward. Can be negative in case of penalty/slashing.
   * @param proof The proof to verify that Vault's reward is correct
   */
  struct HarvestParams {
    bytes32 rewardsRoot;
    int160 reward;
    bytes32[] proof;
  }

  /**
   * @notice Oracles Address
   * @return The address of the Oracles contract
   */
  function oracles() external view returns (IOracles);

  /**
   * @notice Registry Address
   * @return The address of the Registry contract
   */
  function registry() external view returns (IRegistry);

  /**
   * @notice Previous Rewards Root
   * @return The previous merkle tree root of the rewards accumulated by the Vaults in the consensus layer
   */
  function prevRewardsRoot() external view returns (bytes32);

  /**
   * @notice Rewards Root
   * @return The latest merkle tree root of the rewards accumulated by the Vaults in the consensus layer
   */
  function rewardsRoot() external view returns (bytes32);

  /**
   * @notice Rewards Nonce
   * @return The nonce used for updating rewards merkle tree root
   */
  function rewardsNonce() external view returns (uint96);

  /**
   * @notice Get last synced Vault reward
   * @param vault The address of the Vault
   * @return nonce The last synced reward nonce
   * @return reward The last synced reward
   */
  function rewards(address vault) external view returns (uint96 nonce, int160 reward);

  /**
   * @notice Checks whether Vault must be harvested
   * @param vault The address of the Vault
   * @return `true` if the Vault requires harvesting, `false` otherwise
   */
  function isHarvestRequired(address vault) external view returns (bool);

  /**
   * @notice Checks whether the Vault can be harvested
   * @param vault The address of the Vault
   * @return `true` if Vault can be harvested, `false` otherwise
   */
  function canHarvest(address vault) external view returns (bool);

  /**
   * @notice Checks whether the Vault has registered validators
   * @param vault The address of the Vault
   * @return `true` if Vault is collateralized, `false` otherwise
   */
  function isCollateralized(address vault) external view returns (bool);

  /**
   * @notice Update rewards merkle tree root. Can be called only by oracle.
   * @param params The struct containing rewards root update parameters
   */
  function setRewardsRoot(RewardsRootUpdateParams calldata params) external;

  /**
   * @notice Harvest rewards. Can be called only by Vault.
   * @param params The struct containing rewards harvesting parameters
   * @return periodReward The total reward/penalty accumulated by the Vault since the last sync
   */
  function harvest(HarvestParams calldata params) external returns (int256 periodReward);
}
