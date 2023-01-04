// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {IRegistry} from './IRegistry.sol';

/**
 * @title IEthVaultFactory
 * @author StakeWise
 * @notice Defines the interface for the ETH Vault Factory contract
 */
interface IEthVaultFactory {
  /**
   * @notice Event emitted on a Vault creation
   * @param admin The address of the Vault admin
   * @param vault The address of the created Vault
   * @param mevEscrow The address of the MEV escrow contract
   * @param params The Vault creation parameters
   */
  event VaultCreated(
    address indexed admin,
    address indexed vault,
    address indexed mevEscrow,
    VaultParams params
  );

  /**
   * @notice A struct containing a Vault creation parameters
   * @param capacity The Vault stops accepting deposits after exceeding the capacity
   * @param validatorsRoot The validators merkle tree root
   * @param feePercent The fee percent that is charged by the Vault
   * @param name The name of the ERC20 token
   * @param symbol The symbol of the ERC20 token
   * @param validatorsIpfsHash The IPFS hash with all the validators deposit data
   * @param metadataIpfsHash The IPFS hash of the Vault's metadata file
   */
  struct VaultParams {
    uint256 capacity;
    bytes32 validatorsRoot;
    uint16 feePercent;
    string name;
    string symbol;
    string validatorsIpfsHash;
    string metadataIpfsHash;
  }

  /**
   * @notice Returns deployer's nonce
   * @param deployer The address of the Vault deployer
   * @return The nonce of the deployer that is used for the vault and fees escrow creation
   */
  function nonces(address deployer) external view returns (uint256);

  /**
   * @notice Public Ethereum Vault implementation
   * @return The address of the Vault implementation contract
   */
  function publicVaultImpl() external view returns (address);

  /**
   * @notice Create Vault
   * @param params The Vault creation parameters
   * @return vault The address of the created Vault
   */
  function createVault(VaultParams calldata params) external returns (address vault);

  /**
   * @notice Compute Vault and MEV Escrow addresses
   * @param deployer The address of the Vault deployer
   * @return vault The address of the created Vault
   * @return mevEscrow The address of the created MevEscrow
   */
  function computeAddresses(
    address deployer
  ) external view returns (address vault, address mevEscrow);
}
