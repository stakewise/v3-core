// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {IVaultAdmin} from './IVaultAdmin.sol';
import {IVaultVersion} from './IVaultVersion.sol';
import {IVaultFee} from './IVaultFee.sol';
import {IVaultState} from './IVaultState.sol';
import {IVaultValidators} from './IVaultValidators.sol';
import {IVaultEnterExit} from './IVaultEnterExit.sol';
import {IVaultMev} from './IVaultMev.sol';
import {IVaultEthStaking} from './IVaultEthStaking.sol';
import {IVaultEthRestaking} from './IVaultEthRestaking.sol';
import {IMulticall} from './IMulticall.sol';

/**
 * @title IEthRestakeVault
 * @author StakeWise
 * @notice Defines the interface for the EthRestakeVault contract
 */
interface IEthRestakeVault is
  IVaultAdmin,
  IVaultVersion,
  IVaultFee,
  IVaultState,
  IVaultValidators,
  IVaultEnterExit,
  IVaultMev,
  IVaultEthStaking,
  IVaultEthRestaking,
  IMulticall
{
  /**
   * @dev Struct for initializing the EthRestakeVault contract
   * @param capacity The Vault stops accepting deposits after exceeding the capacity
   * @param feePercent The fee percent that is charged by the Vault
   * @param metadataIpfsHash The IPFS hash of the Vault's metadata file
   */
  struct EthRestakeVaultInitParams {
    uint256 capacity;
    uint16 feePercent;
    string metadataIpfsHash;
  }

  /**
   * @notice Initializes or upgrades the EthRestakeVault contract. Must transfer security deposit during the deployment.
   * @param params The encoded parameters for initializing the EthRestakeVault contract
   */
  function initialize(bytes calldata params) external payable;
}
