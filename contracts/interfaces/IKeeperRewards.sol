// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

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
  error InvalidAvgRewardPerSecond();

  /**
   * @notice Event emitted on rewards update
   * @param caller The address of the function caller
   * @param rewardsRoot The new rewards merkle tree root
   * @param avgRewardPerSecond The new average reward per second
   * @param updateTimestamp The update timestamp used for rewards calculation
   * @param nonce The nonce used for verifying signatures
   * @param rewardsIpfsHash The new rewards IPFS hash
   */
  event RewardsUpdated(
    address indexed caller,
    bytes32 indexed rewardsRoot,
    uint256 avgRewardPerSecond,
    uint64 updateTimestamp,
    uint64 nonce,
    string rewardsIpfsHash
  );

  /**
   * @notice Event emitted on Vault harvest
   * @param vault The address of the Vault
   * @param rewardsRoot The rewards merkle tree root
   * @param totalAssetsDelta The Vault total assets delta since last sync. Can be negative in case of penalty/slashing.
   * @param unlockedMevDelta The Vault execution reward that can be withdrawn from shared MEV escrow. Only used by shared MEV Vaults.
   */
  event Harvested(
    address indexed vault,
    bytes32 indexed rewardsRoot,
    int256 totalAssetsDelta,
    uint256 unlockedMevDelta
  );

  /**
   * @notice A struct containing the last synced Vault's cumulative reward
   * @param assets The Vault cumulative reward earned since the start. Can be negative in case of penalty/slashing.
   * @param nonce The nonce of the last sync
   */
  struct Reward {
    int192 assets;
    uint64 nonce;
  }

  /**
   * @notice A struct containing the last unlocked Vault's cumulative execution reward that can be withdrawn from shared MEV escrow. Only used by shared MEV Vaults.
   * @param assets The shared MEV Vault's cumulative execution reward that can be withdrawn
   * @param nonce The nonce of the last sync
   */
  struct UnlockedMevReward {
    uint192 assets;
    uint64 nonce;
  }

  /**
   * @notice A struct containing parameters for rewards update
   * @param rewardsRoot The new rewards merkle root
   * @param avgRewardPerSecond The new average reward per second
   * @param updateTimestamp The update timestamp used for rewards calculation
   * @param rewardsIpfsHash The new IPFS hash with all the Vaults' rewards for the new root
   * @param signatures The concatenation of the Oracles' signatures
   */
  struct RewardsUpdateParams {
    bytes32 rewardsRoot;
    uint256 avgRewardPerSecond;
    uint64 updateTimestamp;
    string rewardsIpfsHash;
    bytes signatures;
  }

  /**
   * @notice A struct containing parameters for harvesting rewards. Can only be called by Vault.
   * @param rewardsRoot The rewards merkle root
   * @param reward The Vault cumulative reward earned since the start. Can be negative in case of penalty/slashing.
   * @param unlockedMevReward The Vault cumulative execution reward that can be withdrawn from shared MEV escrow. Only used by shared MEV Vaults.
   * @param proof The proof to verify that Vault's reward is correct
   */
  struct HarvestParams {
    bytes32 rewardsRoot;
    int160 reward;
    uint160 unlockedMevReward;
    bytes32[] proof;
  }

  /**
   * @notice Previous Rewards Root
   * @return The previous merkle tree root of the rewards accumulated by the Vaults
   */
  function prevRewardsRoot() external view returns (bytes32);

  /**
   * @notice Rewards Root
   * @return The latest merkle tree root of the rewards accumulated by the Vaults
   */
  function rewardsRoot() external view returns (bytes32);

  /**
   * @notice Rewards Nonce
   * @return The nonce used for updating rewards merkle tree root
   */
  function rewardsNonce() external view returns (uint64);

  /**
   * @notice The last rewards update
   * @return The timestamp of the last rewards update
   */
  function lastRewardsTimestamp() external view returns (uint64);

  /**
   * @notice The rewards delay
   * @return The delay in seconds between rewards updates
   */
  function rewardsDelay() external view returns (uint256);

  /**
   * @notice Get last synced Vault cumulative reward
   * @param vault The address of the Vault
   * @return assets The last synced reward assets
   * @return nonce The last synced reward nonce
   */
  function rewards(address vault) external view returns (int192 assets, uint64 nonce);

  /**
   * @notice Get last unlocked shared MEV Vault cumulative reward
   * @param vault The address of the Vault
   * @return assets The last synced reward assets
   * @return nonce The last synced reward nonce
   */
  function unlockedMevRewards(address vault) external view returns (uint192 assets, uint64 nonce);

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
   * @notice Update rewards data
   * @param params The struct containing rewards update parameters
   */
  function updateRewards(RewardsUpdateParams calldata params) external;

  /**
   * @notice Harvest rewards. Can be called only by Vault.
   * @param params The struct containing rewards harvesting parameters
   * @return totalAssetsDelta The total reward/penalty accumulated by the Vault since the last sync
   * @return unlockedMevDelta The Vault execution reward that can be withdrawn from shared MEV escrow. Only used by shared MEV Vaults.
   */
  function harvest(
    HarvestParams calldata params
  ) external returns (int256 totalAssetsDelta, uint256 unlockedMevDelta);
}
