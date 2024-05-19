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
import {IVaultEthStaking} from './IVaultEthStaking.sol';
import {IVaultBlocklist} from './IVaultBlocklist.sol';
import {IMulticall} from './IMulticall.sol';

/**
 * @title IEthFoxVault
 * @author StakeWise
 * @notice Defines the interface for the EthFoxVault contract
 */
interface IEthFoxVault is
  IVaultAdmin,
  IVaultVersion,
  IVaultFee,
  IVaultState,
  IVaultValidators,
  IVaultEnterExit,
  IVaultMev,
  IVaultEthStaking,
  IVaultBlocklist,
  IMulticall
{
  /**
   * @notice Event emitted when a user is ejected from the Vault
   * @param user The address of the user
   * @param shares The amount of shares ejected
   */
  event UserEjected(address user, uint256 shares);

  /**
   * @dev Struct for initializing the EthFoxVault contract
   * @param admin The address of the Vault admin
   * @param ownMevEscrow The address of the MEV escrow contract
   * @param capacity The Vault stops accepting deposits after exceeding the capacity
   * @param feePercent The fee percent that is charged by the Vault
   * @param metadataIpfsHash The IPFS hash of the Vault's metadata file
   */
  struct EthFoxVaultInitParams {
    address admin;
    address ownMevEscrow;
    uint256 capacity;
    uint16 feePercent;
    string metadataIpfsHash;
  }

  /**
   * @notice Event emitted on EthFoxVault creation
   * @param admin The address of the Vault admin
   * @param ownMevEscrow The address of the MEV escrow contract
   * @param capacity The capacity of the Vault
   * @param feePercent The fee percent of the Vault
   * @param metadataIpfsHash The IPFS hash of the Vault metadata
   */
  event EthFoxVaultCreated(
    address admin,
    address ownMevEscrow,
    uint256 capacity,
    uint16 feePercent,
    string metadataIpfsHash
  );

  /**
   * @notice Initializes or upgrades the EthFoxVault contract. Must transfer security deposit during the deployment.
   * @param params The encoded parameters for initializing the EthFoxVault contract
   */
  function initialize(bytes calldata params) external payable;

  /**
   * @notice Ejects user from the Vault. Can only be called by the blocklist manager.
   *         The ejected user will be added to the blocklist and all his shares will be sent to the exit queue.
   * @param user The address of the user to eject
   */
  function ejectUser(address user) external;
}
