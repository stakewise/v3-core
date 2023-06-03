// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {IValidatorsRegistry} from '../interfaces/IValidatorsRegistry.sol';
import {IVaultsRegistry} from '../interfaces/IVaultsRegistry.sol';
import {IOracles} from '../interfaces/IOracles.sol';
import {IOsToken} from '../interfaces/IOsToken.sol';
import {KeeperValidators} from './KeeperValidators.sol';
import {KeeperRewards} from './KeeperRewards.sol';

/**
 * @title Keeper
 * @author StakeWise
 * @notice Defines the functionality for updating Vaults' rewards and approving validators registrations
 */
contract Keeper is KeeperRewards, KeeperValidators {
  /**
   * @dev Constructor
   * @param sharedMevEscrow The address of the shared MEV escrow contract
   * @param oracles The address of the Oracles contract
   * @param vaultsRegistry The address of the VaultsRegistry contract
   * @param osToken The address of the OsToken contract
   * @param validatorsRegistry The address of the beacon chain validators registry contract
   * @param _rewardsDelay The delay in seconds between rewards updates
   * @param maxAvgRewardPerSecond The maximum possible average reward per second
   */
  constructor(
    address sharedMevEscrow,
    IOracles oracles,
    IVaultsRegistry vaultsRegistry,
    IOsToken osToken,
    IValidatorsRegistry validatorsRegistry,
    uint256 _rewardsDelay,
    uint256 maxAvgRewardPerSecond
  )
    KeeperRewards(
      sharedMevEscrow,
      oracles,
      vaultsRegistry,
      osToken,
      _rewardsDelay,
      maxAvgRewardPerSecond
    )
    KeeperValidators(validatorsRegistry)
  {}
}
