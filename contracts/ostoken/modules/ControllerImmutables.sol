// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.18;

import {IControllerImmutables} from '../../interfaces/IControllerImmutables.sol';

/**
 * @title ControllerImmutables
 * @author StakeWise
 * @notice Defines the OsToken controller common immutable variables
 */
abstract contract ControllerImmutables is IControllerImmutables {
  /// @inheritdoc IControllerImmutables
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address public immutable override keeper;

  /// @inheritdoc IControllerImmutables
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address public immutable override vaultsRegistry;

  /// @inheritdoc IControllerImmutables
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address public immutable override osToken;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param _keeper The address of the Keeper contract
   * @param _vaultsRegistry The address of the VaultsRegistry contract
   * @param _osToken The address of the OsToken contract
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(address _keeper, address _vaultsRegistry, address _osToken) {
    keeper = _keeper;
    vaultsRegistry = _vaultsRegistry;
    osToken = _osToken;
  }
}
