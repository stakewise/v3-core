// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {IKeeperRewards} from '../../interfaces/IKeeperRewards.sol';

/**
 * @title VaultImmutables
 * @author StakeWise
 * @notice Defines the Vault common immutable variables
 */
abstract contract VaultImmutables {
  // Custom errors
  error NotHarvested();
  error NotCollateralized();

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address internal immutable _keeper;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address internal immutable _vaultsRegistry;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address internal immutable _validatorsRegistry;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param keeper The address of the Keeper contract
   * @param vaultsRegistry The address of the VaultsRegistry contract
   * @param validatorsRegistry The contract address used for registering validators in beacon chain
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(address keeper, address vaultsRegistry, address validatorsRegistry) {
    _keeper = keeper;
    _vaultsRegistry = vaultsRegistry;
    _validatorsRegistry = validatorsRegistry;
  }

  /**
   * @dev Internal method for checking whether the vault is harvested
   */
  function _checkHarvested() internal view {
    if (IKeeperRewards(_keeper).isHarvestRequired(address(this))) revert NotHarvested();
  }

  /**
   * @dev Internal method for checking whether the vault is collateralized
   */
  function _checkCollateralized() internal view {
    if (!IKeeperRewards(_keeper).isCollateralized(address(this))) revert NotCollateralized();
  }
}
