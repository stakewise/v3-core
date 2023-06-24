// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {IValidatorsRegistry} from '../interfaces/IValidatorsRegistry.sol';
import {IVaultsRegistry} from '../interfaces/IVaultsRegistry.sol';
import {IOsToken} from '../interfaces/IOsToken.sol';
import {IKeeper} from '../interfaces/IKeeper.sol';
import {KeeperValidators} from './KeeperValidators.sol';
import {KeeperRewards} from './KeeperRewards.sol';
import {KeeperOracles} from './KeeperOracles.sol';

/**
 * @title Keeper
 * @author StakeWise
 * @notice Defines the functionality for updating Vaults' rewards and approving validators registrations
 */
contract Keeper is KeeperOracles, KeeperRewards, KeeperValidators, IKeeper {
  /**
   * @dev Constructor
   * @param sharedMevEscrow The address of the shared MEV escrow contract
   * @param vaultsRegistry The address of the VaultsRegistry contract
   * @param osToken The address of the OsToken contract
   * @param _rewardsDelay The delay in seconds between rewards updates
   * @param maxAvgRewardPerSecond The maximum possible average reward per second
   * @param validatorsRegistry The address of the beacon chain validators registry contract
   */
  constructor(
    address sharedMevEscrow,
    IVaultsRegistry vaultsRegistry,
    IOsToken osToken,
    uint256 _rewardsDelay,
    uint256 maxAvgRewardPerSecond,
    IValidatorsRegistry validatorsRegistry
  )
    KeeperOracles()
    KeeperRewards(sharedMevEscrow, vaultsRegistry, osToken, _rewardsDelay, maxAvgRewardPerSecond)
    KeeperValidators(validatorsRegistry)
  {}
}
