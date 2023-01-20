// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {IVaultAdmin} from './IVaultAdmin.sol';
import {IVaultEnterExit} from './IVaultEnterExit.sol';
import {IVaultFee} from './IVaultFee.sol';
import {IVaultImmutables} from './IVaultImmutables.sol';
import {IVaultState} from './IVaultState.sol';
import {IVaultToken} from './IVaultToken.sol';
import {IVaultValidators} from './IVaultValidators.sol';
import {IVaultVersion} from './IVaultVersion.sol';
import {IVaultEthStaking} from './IVaultEthStaking.sol';
import {IMulticall} from './IMulticall.sol';

/**
 * @title IEthVault
 * @author StakeWise
 * @notice Defines the interface for the EthVault contract
 */
interface IEthVault is
  IVaultImmutables,
  IVaultToken,
  IVaultAdmin,
  IVaultVersion,
  IVaultFee,
  IVaultState,
  IVaultValidators,
  IVaultEnterExit,
  IVaultEthStaking,
  IMulticall
{
  /**
   * @dev Struct for initializing the EthVault contract
   * @param capacity The Vault stops accepting deposits after exceeding the capacity
   * @param validatorsRoot The validators Merkle tree root
   * @param admin The address of the Vault admin
   * @param mevEscrow The address of the MEV escrow
   * @param feePercent The fee percent that is charged by the Vault
   * @param name The name of the ERC20 token
   * @param symbol The symbol of the ERC20 token
   * @param validatorsIpfsHash The IPFS hash with all the validators deposit data
   * @param metadataIpfsHash The IPFS hash of the Vault's metadata file
   */
  struct EthVaultInitParams {
    uint256 capacity;
    bytes32 validatorsRoot;
    address admin;
    address mevEscrow;
    uint16 feePercent;
    string name;
    string symbol;
    string validatorsIpfsHash;
    string metadataIpfsHash;
  }

  /**
   * @notice Initializes the EthVault contract
   * @param params The encoded parameters for initializing the EthVault contract
   */
  function initialize(bytes calldata params) external;
}
