// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {IRegistry} from './IRegistry.sol';

/**
 * @title IVaultFactory
 * @author StakeWise
 * @notice Defines the common interface for the Vault Factory contracts
 */
interface IVaultFactory {
  /**
   * @notice Registry contract
   * @return The address of the Registry contract
   */
  function registry() external view returns (IRegistry);

  /**
   * @notice Vault implementation contract
   * @return The address of the Vault implementation contract used for the proxy deployment
   */
  function vaultImplementation() external view returns (address);
}
