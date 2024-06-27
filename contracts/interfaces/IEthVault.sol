// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IKeeperRewards} from './IKeeperRewards.sol';
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
   * @param feePercent The fee percent that is charged by the Vault
   * @param metadataIpfsHash The IPFS hash of the Vault's metadata file
   */
  struct EthVaultInitParams {
    uint256 capacity;
    uint16 feePercent;
    string metadataIpfsHash;
  }

  /**
   * @notice Initializes or upgrades the EthVault contract. Must transfer security deposit during the deployment.
   * @param params The encoded parameters for initializing the EthVault contract
   */
  function initialize(bytes calldata params) external payable;

  /**
   * @notice Deposits assets to the vault and mints OsToken shares to the receiver
   * @param receiver The address to receive the OsToken
   * @param referrer The address of the referrer
   * @return osTokenShares The amount of OsToken shares minted
   */
  function depositAndMintOsToken(
    address receiver,
    address referrer
  ) external payable returns (uint256 osTokenShares);

  /**
   * @notice Updates the state, deposits assets to the vault and mints OsToken shares to the receiver
   * @param receiver The address to receive the OsToken
   * @param referrer The address of the referrer
   * @param harvestParams The parameters for the harvest
   * @return osTokenShares The amount of OsToken shares minted
   */
  function updateStateAndDepositAndMintOsToken(
    address receiver,
    address referrer,
    IKeeperRewards.HarvestParams calldata harvestParams
  ) external payable returns (uint256 osTokenShares);
}
