// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

/**
 * @title IVaultFactory
 * @author StakeWise
 * @notice Defines the interface for the Vault Factory contract
 */
interface IVaultFactory {
  /**
   * @notice Parameters used for the Vault initialization
   * @param name The name of the ERC20 token
   * @param symbol The symbol of the ERC20 token
   * @param operator The address of the Vault operator
   * @param maxTotalAssets The max total assets that can be staked into the Vault
   * @param feePercent The fee percent that is charged by the Vault operator
   */
  struct Parameters {
    string name;
    string symbol;
    address operator;
    uint128 maxTotalAssets;
    uint16 feePercent;
  }

  /**
   * @notice Event emitted on a Vault creation
   * @param caller The address that called the create function
   * @param vault The address of the created Vault
   * @param feesEscrow The address of the Fees Escrow
   * @param name The name of the ERC20 token
   * @param symbol The symbol of the ERC20 symbol
   * @param operator The address of the Vault operator
   * @param maxTotalAssets The max total assets that can be staked into the Vault
   * @param feePercent The fee percent that is charged by the Vault operator
   */
  event VaultCreated(
    address indexed caller,
    address indexed vault,
    address indexed feesEscrow,
    string name,
    string symbol,
    address operator,
    uint128 maxTotalAssets,
    uint16 feePercent
  );

  /**
   * @notice The keeper address that can harvest Vault's rewards
   * @return The address of the Vault keeper
   */
  function keeper() external view returns (address);

  /**
   * @notice The address used for registering Vault's validators
   * @return The address of the validators registry
   */
  function validatorsRegistry() external view returns (address);

  /**
   * @notice Get the parameters to be used in constructing the Vault, set transiently during Vault creation
   * @dev Called by the Vault constructor to fetch the parameters of the Vault
   * @return Parameters The parameters used for Vault initialization
   */
  function parameters() external view returns (Parameters memory);

  /**
   * @notice Create new Vault
   * @param params The parameters used for Vault initialization
   */
  function createVault(Parameters calldata params)
    external
    returns (address vault, address feesEscrow);
}
