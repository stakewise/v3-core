// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

/**
 * @title IVaultFactory
 * @author StakeWise
 * @notice Defines the interface for the Vault Factory contract
 */
interface IVaultFactory {
  /**
   * @notice Event emitted on a Vault creation
   * @param caller The address that called the create function
   * @param vault The address of the created Vault
   * @param operator The address of the Vault operator
   * @param maxTotalAssets The max total assets that can be staked into the Vault
   * @param feePercent The fee percent that is charged by the Vault operator
   */
  event VaultCreated(
    address indexed caller,
    address indexed vault,
    address indexed feesEscrow,
    address operator,
    uint128 maxTotalAssets,
    uint16 feePercent
  );

  /**
   * @notice Last Vault ID
   * @return The ID of the last created Vault
   */
  function lastVaultId() external view returns (uint256);

  /**
   * @notice The keeper address that can harvest Vault's rewards
   * @return The address of the Vault keeper
   */
  function keeper() external view returns (address);

  /**
   * @notice Get the parameters to be used in constructing the Vault, set transiently during pool creation
   * @dev Called by the pool constructor to fetch the parameters of the Vault
   * @return operator The address of the Vault operator
   * @return maxTotalAssets The max total assets that can be staked into the Vault
   * @return feePercent The fee percent that is charged by the Vault operator
   */
  function parameters()
    external
    view
    returns (
      address operator,
      uint128 maxTotalAssets,
      uint16 feePercent
    );

  /**
   * @notice Create new Vault
   * @param operator The address of the Vault operator
   * @param maxTotalAssets The max total assets that can be staked into the Vault
   * @param feePercent The fee percent that is charged by the Vault operator
   * @return vault The address of the created Vault
   * @return feesEscrow The address of the created Vault's fees escrow
   */
  function createVault(
    address operator,
    uint128 maxTotalAssets,
    uint16 feePercent
  ) external returns (address vault, address feesEscrow);

  /**
   * @notice Retrieve Vault address
   * @param vaultId The Vault ID assigned during the deployment
   * @return The address of the Vault
   */
  function getVaultAddress(uint256 vaultId) external view returns (address);
}
