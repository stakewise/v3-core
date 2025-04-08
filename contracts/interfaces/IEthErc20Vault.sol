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
import {IVaultToken} from './IVaultToken.sol';

/**
 * @title IEthErc20Vault
 * @author StakeWise
 * @notice Defines the interface for the EthErc20Vault contract
 */
interface IEthErc20Vault is
  IVaultAdmin,
  IVaultVersion,
  IVaultFee,
  IVaultState,
  IVaultValidators,
  IVaultEnterExit,
  IVaultOsToken,
  IVaultMev,
  IVaultToken,
  IVaultEthStaking,
  IMulticall
{
  /**
   * @dev Struct for deploying the EthErc20Vault contract
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
   * @param exitingAssetsClaimDelay The delay after which the assets can be claimed after exiting from staking
   */
  struct EthErc20VaultConstructorArgs {
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
    uint64 exitingAssetsClaimDelay;
  }

  /**
   * @dev Struct for initializing the EthErc20Vault contract
   * @param capacity The Vault stops accepting deposits after exceeding the capacity
   * @param feePercent The fee percent that is charged by the Vault
   * @param name The name of the ERC20 token
   * @param symbol The symbol of the ERC20 token
   * @param metadataIpfsHash The IPFS hash of the Vault's metadata file
   */
  struct EthErc20VaultInitParams {
    uint256 capacity;
    uint16 feePercent;
    string name;
    string symbol;
    string metadataIpfsHash;
  }

  /**
   * @notice Initializes or upgrades the EthErc20Vault contract. Must transfer security deposit during the deployment.
   * @param params The encoded parameters for initializing the EthErc20Vault contract
   */
  function initialize(bytes calldata params) external payable;

  /**
   * @notice Deposits assets to the vault and mints OsToken shares to the receiver
   * @param receiver The address to receive the OsToken
   * @param osTokenShares The amount of OsToken shares to mint.
   *        If set to type(uint256).max, max OsToken shares will be minted.
   * @param referrer The address of the referrer
   * @return The amount of OsToken assets minted
   */
  function depositAndMintOsToken(
    address receiver,
    uint256 osTokenShares,
    address referrer
  ) external payable returns (uint256);

  /**
   * @notice Updates the state, deposits assets to the vault and mints OsToken shares to the receiver
   * @param receiver The address to receive the OsToken
   * @param osTokenShares The amount of OsToken shares to mint.
   *        If set to type(uint256).max, max OsToken shares will be minted.
   * @param referrer The address of the referrer
   * @param harvestParams The parameters for the harvest
   * @return The amount of OsToken assets minted
   */
  function updateStateAndDepositAndMintOsToken(
    address receiver,
    uint256 osTokenShares,
    address referrer,
    IKeeperRewards.HarvestParams calldata harvestParams
  ) external payable returns (uint256);
}
