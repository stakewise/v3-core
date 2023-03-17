// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {IOracles} from './IOracles.sol';
import {IVaultsRegistry} from './IVaultsRegistry.sol';

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
  error TooEarlyUpdate();

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
   * @param consensusAssets The Vault cumulative consensus reward. Can be negative in case of penalty/slashing.
   * @param executionAssets The Vault cumulative shared execution reward. Can be negative in case of penalty/slashing. Only used by shared MEV Vaults.
   */
  event Harvested(
    address indexed vault,
    bytes32 indexed rewardsRoot,
    int160 consensusAssets,
    int160 executionAssets
  );

  /**
   * @notice Event emitted on the update of rewards delay
   * @param caller The address of the function caller
   * @param rewardsDelay The new rewards update delay
   */
  event RewardsDelayUpdated(address indexed caller, uint64 rewardsDelay);

  /**
   * @notice A struct containing the last synced Vault's consensus reward
   * @param assets The total amount of assets earned in consensus layer. Can be negative in case of penalty.
   * @param nonce The nonce of the last sync
   */
  struct ConsensusReward {
    int160 assets;
    uint96 nonce;
  }

  /**
   * @notice A struct containing the last synced Vault's execution reward. Only used by shared MEV Vaults.
   * @param assets The total amount of assets earned in execution layer. Can be negative in case of penalty.
   * @param nonce The nonce of the last sync
   */
  struct ExecutionReward {
    int160 assets;
    uint96 nonce;
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
   * @param consensusAssets The Vault cumulative consensus reward. Can be negative in case of penalty/slashing.
   * @param executionAssets The Vault cumulative shared execution reward. Can be negative in case of penalty/slashing. Only used by shared MEV Vaults.
   * @param proof The proof to verify that Vault's reward is correct
   */
  struct HarvestParams {
    bytes32 rewardsRoot;
    int160 consensusAssets;
    int160 executionAssets;
    bytes32[] proof;
  }

  /**
   * @notice A struct containing harvesting deltas
   * @param consensus The rewards delta for the consensus layer
   * @param execution The rewards delta for the execution layer. Only used by shared MEV Vaults.
   */
  struct HarvestDeltas {
    int128 consensus;
    int128 execution;
  }

  /**
   * @notice Oracles Address
   * @return The address of the Oracles contract
   */
  function oracles() external view returns (IOracles);

  /**
   * @notice Vaults Registry Address
   * @return The address of the Vaults Registry contract
   */
  function vaultsRegistry() external view returns (IVaultsRegistry);

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
   * @notice The last rewards update
   * @return The timestamp of the last rewards update
   */
  function lastRewardsTimestamp() external view returns (uint64);

  /**
   * @notice The rewards delay
   * @return The delay between rewards updates
   */
  function rewardsDelay() external view returns (uint64);

  /**
   * @notice Get last synced Vault consensus rewards
   * @param vault The address of the Vault
   * @return nonce The last synced reward nonce
   * @return reward The last synced reward assets
   */
  function consensusRewards(address vault) external view returns (uint96 nonce, int160 assets);

  /**
   * @notice Get last synced shared MEV Vault execution rewards
   * @param vault The address of the Vault
   * @return nonce The last synced reward nonce
   * @return reward The last synced reward assets
   */
  function executionRewards(address vault) external view returns (uint96 nonce, int160 assets);

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
   * @notice Checks whether rewards can be updated
   * @return `true` if rewards can be updated, `false` otherwise
   */
  function canUpdateRewards() external view returns (bool);

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
   * @notice Update rewards delay. Can only be called by the owner.
   * @param _rewardsDelay The new rewards update delay
   */
  function setRewardsDelay(uint64 _rewardsDelay) external;

  /**
   * @notice Harvest rewards. Can be called only by Vault.
   * @param params The struct containing rewards harvesting parameters
   * @return deltas The consensus and execution deltas
   */
  function harvest(HarvestParams calldata params) external returns (HarvestDeltas memory deltas);
}
