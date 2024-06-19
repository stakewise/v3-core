// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity =0.8.22;

/**
 * @title IRewardGnoToken
 * @author StakeWise
 * @dev Copied from https://github.com/stakewise/contracts/blob/gnosis-chain/contracts/interfaces/IRewardToken.sol
 * @notice Defines the interface for the RewardGnoToken contract
 */
interface IRewardGnoToken {
  /**
   * @dev Function for getting the total assets.
   */
  function totalAssets() external view returns (uint256);

  /**
   * @dev Function for retrieving the total rewards amount.
   */
  function totalRewards() external view returns (uint128);

  /**
   * @dev Function for getting the total penalty.
   */
  function totalPenalty() external view returns (uint256);

  /**
   * @dev Function for updating validators total rewards.
   * Can only be called by Vault contract.
   * @param rewardsDelta - the total rewards earned or penalties received.
   */
  function updateTotalRewards(int256 rewardsDelta) external;
}
