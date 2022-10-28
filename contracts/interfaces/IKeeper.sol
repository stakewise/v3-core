// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {ISigners} from './ISigners.sol';
import {IRegistry} from './IRegistry.sol';

/**
 * @title IKeeper
 * @author StakeWise
 * @notice Defines the interface for the Keeper contract
 */
interface IKeeper {
  // Custom errors
  error InvalidRewardsRoot();
  error InvalidProof();
  error InvalidVault();
  error InvalidValidatorsRegistryRoot();

  /**
   * @notice Event emitted on rewards root update
   * @param caller The address of the rewards root update caller
   * @param rewardsRoot The new rewards Merkle Tree root
   * @param nonce The nonce used for verifying signatures
   * @param rewardsIpfsHash The new rewards IPFS hash
   * @param signatures The concatenation of Signers' signatures
   */
  event RewardsRootUpdated(
    address indexed caller,
    bytes32 indexed rewardsRoot,
    uint256 nonce,
    string rewardsIpfsHash,
    bytes signatures
  );

  /**
   * @notice Event emitted on Vault harvest
   * @param caller The address of the harvest caller
   * @param vault The address of the Vault
   * @param reward The cumulative reward/penalty accumulated by the Vault
   */
  event Harvested(address indexed caller, address indexed vault, int160 reward);

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
   * @notice Signers Address
   * @return The address of the Signers contract
   */
  function signers() external view returns (ISigners);

  /**
   * @notice Registry Address
   * @return The address of the Registry contract
   */
  function registry() external view returns (IRegistry);

  /**
   * @notice Rewards Root
   * @return The latest Merkle Tree root of the rewards accumulated by the Vaults in the consensus layer
   */
  function rewardsRoot() external view returns (bytes32);

  /**
   * @notice Rewards Nonce
   * @return The nonce used for updating rewards Merkle Tree root
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
   * @notice Checks whether the Vault is harvested
   * @param vault The address of the Vault
   * @return `true` if vault is harvested, `false` otherwise
   */
  function isHarvested(address vault) external view returns (bool);

  /**
   * @notice Update Merkle Tree Rewards Root
   * @param _rewardsRoot The new rewards Merkle root
   * @param rewardsIpfsHash The new IPFS hash with all the Vaults' rewards for the new root
   * @param signatures The concatenation of the Signers' signatures
   */
  function setRewardsRoot(
    bytes32 _rewardsRoot,
    string calldata rewardsIpfsHash,
    bytes calldata signatures
  ) external;

  /**
   * @notice Harvest Vault rewards
   * @param vault The address of the Vault to harvest
   * @param vaultReward The Vault cumulative reward. Can be negative in case of penalty/slashing.
   * @param proof The proof to verify that Vault's reward is correct
   * @return The total reward/penalty accumulated by the Vault since the last sync
   */
  function harvest(
    address vault,
    int160 vaultReward,
    bytes32[] calldata proof
  ) external returns (int256);
}
