// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IValidatorsRegistry} from '../interfaces/IValidatorsRegistry.sol';
import {IVaultsRegistry} from '../interfaces/IVaultsRegistry.sol';
import {IOracles} from '../interfaces/IOracles.sol';
import {IKeeper} from '../interfaces/IKeeper.sol';
import {Versioned} from '../base/Versioned.sol';
import {KeeperValidators} from './KeeperValidators.sol';
import {KeeperRewards} from './KeeperRewards.sol';

/**
 * @title Keeper
 * @author StakeWise
 * @notice Defines the functionality for updating Vaults' rewards and approving validators registrations
 */
contract Keeper is Initializable, Versioned, KeeperRewards, KeeperValidators, IKeeper {
  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param sharedMevEscrow The address of the shared MEV escrow contract
   * @param oracles The address of the Oracles contract
   * @param vaultsRegistry The address of the VaultsRegistry contract
   * @param validatorsRegistry The address of the beacon chain validators registry contract
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address sharedMevEscrow,
    IOracles oracles,
    IVaultsRegistry vaultsRegistry,
    IValidatorsRegistry validatorsRegistry
  ) KeeperValidators(sharedMevEscrow, oracles, vaultsRegistry, validatorsRegistry) {
    // disable initializers for the implementation contract
    _disableInitializers();
  }

  /// @inheritdoc IKeeper
  function initialize(address _owner, uint64 _rewardsDelay) external override initializer {
    __KeeperRewards_init(_owner, _rewardsDelay);
  }

  /// @inheritdoc UUPSUpgradeable
  function _authorizeUpgrade(address) internal override onlyOwner {}
}
