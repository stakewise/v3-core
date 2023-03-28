// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {IVaultsRegistry} from './IVaultsRegistry.sol';

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
   * @param isPrivate Defines whether the Vault is private or not
   * @param mevEscrow The address of the MEV escrow contract. Zero address if shared MEV escrow is used.
   * @param capacity The Vault stops accepting deposits after exceeding the capacity
   * @param feePercent The fee percent that is charged by the Vault
   * @param name The name of the ERC20 token
   * @param symbol The symbol of the ERC20 token
   */
  event VaultCreated(
    address indexed admin,
    address indexed vault,
    bool indexed isPrivate,
    address mevEscrow,
    uint256 capacity,
    uint16 feePercent,
    string name,
    string symbol
  );

  /**
   * @notice A struct containing a Vault creation parameters
   * @param capacity The Vault stops accepting deposits after exceeding the capacity
   * @param validatorsRoot The validators merkle tree root
   * @param feePercent The fee percent that is charged by the Vault
   * @param name The name of the ERC20 token
   * @param symbol The symbol of the ERC20 token
   * @param metadataIpfsHash The IPFS hash of the Vault's metadata file
   */
  struct VaultParams {
    uint256 capacity;
    bytes32 validatorsRoot;
    uint16 feePercent;
    string name;
    string symbol;
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
   * @return The address of the public Vault implementation contract
   */
  function publicVaultImpl() external view returns (address);

  /**
   * @notice Private Ethereum Vault implementation
   * @return The address of the private Vault implementation contract
   */
  function privateVaultImpl() external view returns (address);

  /**
   * @notice Create Vault. Must transfer security deposit together with a call.
   * @param params The Vault creation parameters
   * @param isPrivate Defines whether the Vault is private or not
   * @param isOwnMevEscrow Defines whether the Vault has its own MEV escrow
   * @return vault The address of the created Vault
   */
  function createVault(
    VaultParams calldata params,
    bool isPrivate,
    bool isOwnMevEscrow
  ) external payable returns (address vault);

  /**
   * @notice Compute Vault and MEV Escrow addresses
   * @param deployer The address of the Vault deployer
   * @param isPrivate Defines whether the Vault is private or not
   * @return vault The address of the created Vault
   * @return ownMevEscrow The address of the own MevEscrow
   */
  function computeAddresses(
    address deployer,
    bool isPrivate
  ) external view returns (address vault, address ownMevEscrow);
}
