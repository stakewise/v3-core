// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IVaultAdmin} from './IVaultAdmin.sol';
import {IVaultVersion} from './IVaultVersion.sol';
import {IVaultFee} from './IVaultFee.sol';
import {IVaultState} from './IVaultState.sol';
import {IVaultValidators} from './IVaultValidators.sol';
import {IVaultEnterExit} from './IVaultEnterExit.sol';
import {IVaultOsToken} from './IVaultOsToken.sol';
import {IVaultMev} from './IVaultMev.sol';
import {IVaultGnoStaking} from './IVaultGnoStaking.sol';
import {IMulticall} from './IMulticall.sol';

/**
 * @title IGnoVault
 * @author StakeWise
 * @notice Defines the interface for the GnoVault contract
 */
interface IGnoVault is
  IVaultAdmin,
  IVaultVersion,
  IVaultFee,
  IVaultState,
  IVaultValidators,
  IVaultEnterExit,
  IVaultOsToken,
  IVaultMev,
  IVaultGnoStaking,
  IMulticall
{
  /**
   * @dev Struct for initializing the GnoVault contract
   * @param capacity The Vault stops accepting deposits after exceeding the capacity
   * @param feePercent The fee percent that is charged by the Vault
   * @param metadataIpfsHash The IPFS hash of the Vault's metadata file
   */
  struct GnoVaultInitParams {
    uint256 capacity;
    uint16 feePercent;
    string metadataIpfsHash;
  }

  /**
   * @notice Initializes or upgrades the GnoVault contract. Must transfer security deposit during the deployment.
   * @param params The encoded parameters for initializing the GnoVault contract
   */
  function initialize(bytes calldata params) external;
}
