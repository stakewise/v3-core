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
   * @param feesEscrow The address of the fees escrow contract
   * @param params The Vault creation parameters
   */
  event VaultCreated(
    address indexed admin,
    address indexed vault,
    address indexed feesEscrow,
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
   * @notice Vault implementation contract
   * @return The address of the Vault implementation contract used for the proxy deployment
   */
  function vaultImplementation() external view returns (address);

  /**
   * @notice Registry contract
   * @return The address of the Registry contract
   */
  function registry() external view returns (IRegistry);

  /**
   * @notice Returns deployer's nonce
   * @param deployer The address of the Vault deployer
   * @return The nonce of the deployer that is used for the vault and fees escrow creation
   */
  function nonces(address deployer) external view returns (uint256);

  /**
   * @notice Create Vault
   * @param params The Vault creation parameters
   * @return vault The address of the created Vault
   * @return feesEscrow The address of the created FeesEscrow
   */
  function createVault(
    VaultParams calldata params
  ) external returns (address vault, address feesEscrow);

  /**
   * @notice Compute Vault and Fees Escrow addresses
   * @param deployer The address of the Vault deployer
   * @return vault The address of the next created Vault
   * @return feesEscrow The address of the next created FeesEscrow
   */
  function computeAddresses(
    address deployer
  ) external view returns (address vault, address feesEscrow);
}
