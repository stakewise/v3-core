// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.18;

import {IKeeper} from '../../interfaces/IKeeper.sol';
import {IOsToken} from '../../interfaces/IOsToken.sol';
import {IVaultsRegistry} from '../../interfaces/IVaultsRegistry.sol';

/**
 * @title ControllerImmutables
 * @author StakeWise
 * @notice Defines the OsToken controller common immutable variables
 */
abstract contract ControllerImmutables {
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IKeeper internal immutable _keeper;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IVaultsRegistry internal immutable _vaultsRegistry;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IOsToken internal immutable _osToken;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param keeper The address of the Keeper contract
   * @param vaultsRegistry The address of the VaultsRegistry contract
   * @param osToken The address of the OsToken contract
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(address keeper, address vaultsRegistry, address osToken) {
    _keeper = IKeeper(keeper);
    _vaultsRegistry = IVaultsRegistry(vaultsRegistry);
    _osToken = IOsToken(osToken);
  }
}
