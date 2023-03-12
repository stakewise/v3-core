// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {IKeeperValidators} from './IKeeperValidators.sol';
import {IKeeperRewards} from './IKeeperRewards.sol';

/**
 * @title IKeeper
 * @author StakeWise
 * @notice Defines the interface for the Keeper contract
 */
interface IKeeper is IKeeperRewards, IKeeperValidators {
  /**
   * @notice Initializes the Keeper contract
   * @param _owner The address of the Keeper owner
   * @param _rewardsDelay The rewards update delay
   */
  function initialize(address _owner, uint64 _rewardsDelay) external;
}
