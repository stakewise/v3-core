// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IVersioned} from '../interfaces/IVersioned.sol';
import {IValidatorsRegistry} from '../interfaces/IValidatorsRegistry.sol';
import {IVaultsRegistry} from '../interfaces/IVaultsRegistry.sol';
import {IOracles} from '../interfaces/IOracles.sol';
import {IKeeper} from '../interfaces/IKeeper.sol';
import {IOsToken} from '../interfaces/IOsToken.sol';
import {Versioned} from '../base/Versioned.sol';
import {KeeperValidators} from './KeeperValidators.sol';
import {KeeperRewards} from './KeeperRewards.sol';

/**
 * @title Keeper
 * @author StakeWise
 * @notice Defines the functionality for updating Vaults' rewards and approving validators registrations
 */
contract Keeper is Initializable, Versioned, KeeperRewards, KeeperValidators, IKeeper {
  /// @inheritdoc IVersioned
  uint8 public constant override version = 1;

  /// @inheritdoc IKeeper
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address public immutable override dao;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param sharedMevEscrow The address of the shared MEV escrow contract
   * @param oracles The address of the Oracles contract
   * @param vaultsRegistry The address of the VaultsRegistry contract
   * @param osToken The address of the OsToken contract
   * @param validatorsRegistry The address of the beacon chain validators registry contract
   * @param _dao The address of the DAO contract
   * @param _rewardsDelay The delay in seconds between rewards updates
   * @param maxAvgRewardPerSecond The maximum possible average reward per second
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address sharedMevEscrow,
    IOracles oracles,
    IVaultsRegistry vaultsRegistry,
    IOsToken osToken,
    IValidatorsRegistry validatorsRegistry,
    address _dao,
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
  {
    dao = _dao;
    // disable initializers for the implementation contract
    _disableInitializers();
  }

  /// @inheritdoc IKeeper
  function initialize() external override initializer {
    __KeeperRewards_init();
  }

  /// @inheritdoc UUPSUpgradeable
  function _authorizeUpgrade(address) internal view override {
    if (msg.sender != dao) revert AccessDenied();
  }
}
