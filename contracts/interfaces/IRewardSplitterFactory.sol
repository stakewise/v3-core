// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

/**
 * @title IRewardSplitterFactory
 * @author StakeWise
 * @notice Defines the interface for the RewardSplitterFactory contract
 */
interface IRewardSplitterFactory {
  /**
   * @notice Event emitted on a RewardSplitter creation
   * @param owner The address of the RewardSplitter owner
   * @param vault The address of the connected vault
   * @param rewardSplitter The address of the created RewardSplitter
   */
  event RewardSplitterCreated(address owner, address vault, address rewardSplitter);

  /**
   * @notice The address of the RewardSplitter implementation contract used for proxy creation
   * @return The address of the RewardSplitter proxy contract
   */
  function implementation() external view returns (address);

  /**
   * @notice Creates RewardSplitter contract proxy
   * @param vault The address of the vault to which the RewardSplitter will be connected
   * @return rewardSplitter The address of the created RewardSplitter contract
   */
  function createRewardSplitter(address vault) external returns (address rewardSplitter);
}
