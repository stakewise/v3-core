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
   * @notice Struct for initializing the GnoVault contract
   * @param keeper The address of the Keeper contract
   * @param vaultsRegistry The address of the VaultsRegistry contract
   * @param validatorsRegistry The contract address used for registering validators in beacon chain
   * @param validatorsWithdrawals The contract address used for withdrawing validators in beacon chain
   * @param validatorsConsolidations The contract address used for consolidating validators in beacon chain
   * @param consolidationsChecker The contract address used for checking consolidations
   * @param osTokenVaultController The address of the OsTokenVaultController contract
   * @param osTokenConfig The address of the OsTokenConfig contract
   * @param osTokenVaultEscrow The address of the OsTokenVaultEscrow contract
   * @param sharedMevEscrow The address of the shared MEV escrow
   * @param depositDataRegistry The address of the DepositDataRegistry contract
   * @param gnoToken The address of the GNO token
   * @param gnoDaiDistributor The address of the GnoDaiDistributor contract
   * @param exitingAssetsClaimDelay The delay after which the assets can be claimed after exiting from staking
   */
  struct GnoVaultConstructorArgs {
    address keeper;
    address vaultsRegistry;
    address validatorsRegistry;
    address validatorsWithdrawals;
    address validatorsConsolidations;
    address consolidationsChecker;
    address osTokenVaultController;
    address osTokenConfig;
    address osTokenVaultEscrow;
    address sharedMevEscrow;
    address depositDataRegistry;
    address gnoToken;
    address gnoDaiDistributor;
    uint256 exitingAssetsClaimDelay;
  }

  /**
   * @notice Struct for initializing the GnoVault contract
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
