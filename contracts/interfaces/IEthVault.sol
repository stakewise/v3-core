// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {IVaultToken} from './IVaultToken.sol';
import {IVaultAdmin} from './IVaultAdmin.sol';
import {IVaultVersion} from './IVaultVersion.sol';
import {IVaultFee} from './IVaultFee.sol';
import {IVaultState} from './IVaultState.sol';
import {IVaultValidators} from './IVaultValidators.sol';
import {IVaultEnterExit} from './IVaultEnterExit.sol';
import {IVaultOsToken} from './IVaultOsToken.sol';
import {IVaultMev} from './IVaultMev.sol';
import {IVaultEthStaking} from './IVaultEthStaking.sol';
import {IMulticall} from './IMulticall.sol';

/**
 * @title IEthVault
 * @author StakeWise
 * @notice Defines the interface for the EthVault contract
 */
interface IEthVault is
  IVaultToken,
  IVaultAdmin,
  IVaultVersion,
  IVaultFee,
  IVaultState,
  IVaultValidators,
  IVaultEnterExit,
  IVaultOsToken,
  IVaultMev,
  IVaultEthStaking,
  IMulticall
{
  /**
   * @dev Struct for initializing the EthVault contract
   * @param capacity The Vault stops accepting deposits after exceeding the capacity
   * @param admin The address of the Vault admin
   * @param mevEscrow The address of the MEV escrow
   * @param feePercent The fee percent that is charged by the Vault
   * @param name The name of the ERC20 token
   * @param symbol The symbol of the ERC20 token
   * @param metadataIpfsHash The IPFS hash of the Vault's metadata file
   */
  struct EthVaultInitParams {
    uint256 capacity;
    address admin;
    address mevEscrow;
    uint16 feePercent;
    string name;
    string symbol;
    string metadataIpfsHash;
  }

  /**
   * @notice Initializes the EthVault contract. Must transfer security deposit together with a call.
   * @param params The encoded parameters for initializing the EthVault contract
   */
  function initialize(bytes calldata params) external payable;
}
