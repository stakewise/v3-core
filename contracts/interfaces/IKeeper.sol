// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IKeeperOracles} from './IKeeperOracles.sol';
import {IKeeperValidators} from './IKeeperValidators.sol';
import {IKeeperRewards} from './IKeeperRewards.sol';

/**
 * @title IKeeper
 * @author StakeWise
 * @notice Defines the interface for the Keeper contract
 */
interface IKeeper is IKeeperOracles, IKeeperRewards, IKeeperValidators {
  /**
   * @notice Initializes the Keeper contract. Can only be called once.
   * @param _owner The address of the owner
   */
  function initialize(address _owner) external;
}
