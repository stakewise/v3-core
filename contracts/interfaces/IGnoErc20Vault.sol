// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

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
import {IVaultToken} from './IVaultToken.sol';

/**
 * @title IGnoErc20Vault
 * @author StakeWise
 * @notice Defines the interface for the GnoErc20Vault contract
 */
interface IGnoErc20Vault is
  IVaultAdmin,
  IVaultVersion,
  IVaultFee,
  IVaultState,
  IVaultValidators,
  IVaultEnterExit,
  IVaultOsToken,
  IVaultMev,
  IVaultToken,
  IVaultGnoStaking,
  IMulticall
{
  /**
   * @dev Struct for initializing the GnoErc20Vault contract
   * @param capacity The Vault stops accepting deposits after exceeding the capacity
   * @param feePercent The fee percent that is charged by the Vault
   * @param name The name of the ERC20 token
   * @param symbol The symbol of the ERC20 token
   * @param metadataIpfsHash The IPFS hash of the Vault's metadata file
   */
  struct GnoErc20VaultInitParams {
    uint256 capacity;
    uint16 feePercent;
    string name;
    string symbol;
    string metadataIpfsHash;
  }

  /**
   * @notice Initializes or upgrades the GnoErc20Vault contract. Must transfer security deposit during the deployment.
   * @param params The encoded parameters for initializing the GnoErc20Vault contract
   */
  function initialize(bytes calldata params) external;
}
