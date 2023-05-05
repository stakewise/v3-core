// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {IVersioned} from './IVersioned.sol';
import {IVaultAdmin} from './IVaultAdmin.sol';

/**
 * @title IVaultVersion
 * @author StakeWise
 * @notice Defines the interface for VaultVersion contract
 */
interface IVaultVersion is IVersioned, IVaultAdmin {
  // Custom errors
  error UpgradeFailed();

  /**
   * @notice Vault Unique Identifier
   * @return The unique identifier of the Vault
   */
  function vaultId() external pure returns (bytes32);
}
