// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

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
   * @param feesEscrow The address of the Fees Escrow
   * @param name The name of the ERC20 token
   * @param symbol The symbol of the ERC20 symbol
   * @param maxTotalAssets The max total assets that can be staked into the Vault
   * @param feePercent The fee percent that is charged by the Vault operator
   */
  event VaultCreated(
    address indexed operator,
    address indexed vault,
    address indexed feesEscrow,
    string name,
    string symbol,
    uint256 maxTotalAssets,
    uint16 feePercent
  );

  /**
   * @notice Vault implementation contract
   * @return The address of the Vault implementation contract used for the proxy deployment
   */
  function vaultImplementation() external view returns (address);

  /**
   * @notice Create Vault
   * @param _name The name of the ERC20 token
   * @param _symbol The symbol of the ERC20 token
   * @param _maxTotalAssets The max total assets that can be staked into the Vault
   * @param _feePercent The fee percent that is charged by the Vault operator
   * @return vault The address of the created Vault
   * @return feesEscrow The address of the created fees escrow
   */
  function createVault(
    string memory _name,
    string memory _symbol,
    uint256 _maxTotalAssets,
    uint16 _feePercent
  ) external returns (address vault, address feesEscrow);
}
