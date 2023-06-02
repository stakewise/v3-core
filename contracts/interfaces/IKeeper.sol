// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {IKeeperValidators} from './IKeeperValidators.sol';
import {IKeeperRewards} from './IKeeperRewards.sol';
import {IVersioned} from './IVersioned.sol';

/**
 * @title IKeeper
 * @author StakeWise
 * @notice Defines the interface for the Keeper contract
 */
interface IKeeper is IVersioned, IKeeperRewards, IKeeperValidators {
  /**
   * @notice DAO contract
   * @return The address of the DAO contract
   */
  function dao() external view returns (address);

  /**
   * @notice Initializes the Keeper contract
   */
  function initialize() external;
}
