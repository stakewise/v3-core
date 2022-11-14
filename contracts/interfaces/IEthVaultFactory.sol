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
   * @param operator The address of the Vault operator
   * @param vault The address of the created Vault
   * @param feesEscrow The address of the fees escrow contract
   * @param maxTotalAssets The max total assets that can be staked into the Vault
   * @param validatorsRoot The validators merkle tree root
   * @param feePercent The fee percent that is charged by the Vault operator
   * @param name The name of the ERC20 token
   * @param symbol The symbol of the ERC20 token
   * @param validatorsIpfsHash The IPFS hash with all the validators deposit data
   */
  event VaultCreated(
    address indexed operator,
    address indexed vault,
    address indexed feesEscrow,
    uint256 maxTotalAssets,
    bytes32 validatorsRoot,
    uint16 feePercent,
    string name,
    string symbol,
    string validatorsIpfsHash
  );

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
   * @notice Returns operator's nonce
   * @param operator The address of the operator
   * @return The nonce of the operator that is used for the vault and fees escrow creation
   */
  function nonces(address operator) external view returns (uint256);

  /**
   * @notice Create Vault
   * @param maxTotalAssets The max total assets that can be staked into the Vault
   * @param validatorsRoot The validators merkle tree root
   * @param feePercent The fee percent that is charged by the Vault operator
   * @param name The name of the ERC20 token
   * @param symbol The symbol of the ERC20 token
   * @param validatorsIpfsHash The IPFS hash with all the validators deposit data
   * @return vault The address of the created Vault
   * @return feesEscrow The address of the created FeesEscrow
   */
  function createVault(
    uint256 maxTotalAssets,
    bytes32 validatorsRoot,
    uint16 feePercent,
    string calldata name,
    string calldata symbol,
    string calldata validatorsIpfsHash
  ) external returns (address vault, address feesEscrow);

  /**
   * @notice Compute Vault and Fees Escrow addresses
   * @param operator The address of the Vault operator
   * @return vault The address of the next created Vault
   * @return feesEscrow The address of the next created FeesEscrow
   */
  function computeAddresses(address operator)
    external
    view
    returns (address vault, address feesEscrow);
}
