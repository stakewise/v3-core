// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.18;

import {IVaultImmutables} from '../../interfaces/IVaultImmutables.sol';

/**
 * @title VaultImmutables
 * @author StakeWise
 * @notice Defines the Vault common immutable variables
 */
abstract contract VaultImmutables is IVaultImmutables {
  /// @inheritdoc IVaultImmutables
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address public immutable override keeper;

  /// @inheritdoc IVaultImmutables
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address public immutable override vaultsRegistry;

  /// @inheritdoc IVaultImmutables
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address public immutable override validatorsRegistry;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param _keeper The address of the Keeper contract
   * @param _vaultsRegistry The address of the VaultsRegistry contract
   * @param _validatorsRegistry The contract address used for registering validators in beacon chain
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(address _keeper, address _vaultsRegistry, address _validatorsRegistry) {
    keeper = _keeper;
    vaultsRegistry = _vaultsRegistry;
    validatorsRegistry = _validatorsRegistry;
  }
}
