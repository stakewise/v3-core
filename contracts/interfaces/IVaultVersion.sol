// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {IERC1822Proxiable} from '@openzeppelin/contracts/interfaces/draft-IERC1822.sol';
import {IVaultAdmin} from './IVaultAdmin.sol';

/**
 * @title IVaultVersion
 * @author StakeWise
 * @notice Defines the interface for VaultVersion contract
 */
interface IVaultVersion is IERC1822Proxiable, IVaultAdmin {
  /**
   * @notice Vault Unique Identifier
   * @return The unique identifier of the Vault
   */
  function vaultId() external pure returns (bytes32);

  /**
   * @notice Version
   * @return The version of the Vault implementation contract
   */
  function version() external pure returns (uint8);

  /**
   * @notice Implementation
   * @return The address of the Vault implementation contract
   */
  function implementation() external view returns (address);
}
