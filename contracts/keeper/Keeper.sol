// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {IValidatorsRegistry} from '../interfaces/IValidatorsRegistry.sol';
import {IOracles} from '../interfaces/IOracles.sol';
import {IKeeper} from '../interfaces/IKeeper.sol';
import {IVaultsRegistry} from '../interfaces/IVaultsRegistry.sol';
import {Versioned} from '../base/Versioned.sol';
import {KeeperValidators} from './KeeperValidators.sol';
import {KeeperRewards} from './KeeperRewards.sol';

/**
 * @title Keeper
 * @author StakeWise
 * @notice Defines the functionality for updating Vaults' consensus rewards and approving validators registrations
 */
contract Keeper is
  Initializable,
  OwnableUpgradeable,
  Versioned,
  KeeperRewards,
  KeeperValidators,
  IKeeper
{
  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param _oracles The address of the Oracles contract
   * @param _vaultsRegistry The address of the VaultsRegistry contract
   * @param _validatorsRegistry The address of the beacon chain validators registry contract
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    IOracles _oracles,
    IVaultsRegistry _vaultsRegistry,
    IValidatorsRegistry _validatorsRegistry
  ) KeeperValidators(_oracles, _vaultsRegistry, _validatorsRegistry) {
    // disable initializers for the implementation contract
    _disableInitializers();
  }

  /// @inheritdoc IKeeper
  function initialize(address _owner) external override initializer {
    _transferOwnership(_owner);

    // set rewardsNonce to 1 so that vaults collateralized
    // before first rewards root update will not have 0 nonce
    rewardsNonce = 1;
  }

  /// @inheritdoc UUPSUpgradeable
  function _authorizeUpgrade(address) internal override onlyOwner {}
}
