// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {IVaultFactory} from './IVaultFactory.sol';

/**
 * @title IEthVaultFactory
 * @author StakeWise
 * @notice Defines the interface for the ETH Vault Factory contract
 */
interface IEthVaultFactory is IVaultFactory {
  /**
   * @notice Event emitted on a Vault creation
   * @param operator The address of the Vault operator
   * @param vault The address of the created Vault
   * @param name The name of the ERC20 token
   * @param symbol The symbol of the ERC20 symbol
   * @param maxTotalAssets The max total assets that can be staked into the Vault
   * @param feePercent The fee percent that is charged by the Vault operator
   */
  event VaultCreated(
    address indexed operator,
    address indexed vault,
    string name,
    string symbol,
    uint256 maxTotalAssets,
    uint16 feePercent
  );

  /**
   * @notice Create Vault
   * @param _name The name of the ERC20 token
   * @param _symbol The symbol of the ERC20 token
   * @param _maxTotalAssets The max total assets that can be staked into the Vault
   * @param _feePercent The fee percent that is charged by the Vault operator
   * @return vault The address of the created Vault
   */
  function createVault(
    string memory _name,
    string memory _symbol,
    uint256 _maxTotalAssets,
    uint16 _feePercent
  ) external returns (address vault);
}
