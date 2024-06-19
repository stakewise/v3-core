// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

/**
 * @title IEthRestakeVaultFactory
 * @author StakeWise
 * @notice Defines the interface for the EthRestakeVaultFactory contract
 */
interface IEthRestakeVaultFactory {
  /**
   * @notice Event emitted on a Vault creation
   * @param admin The address of the Vault admin
   * @param vault The address of the created Vault
   * @param ownMevEscrow The address of the own MEV escrow contract. Zero address if shared MEV escrow is used.
   * @param params The encoded parameters for initializing the Vault contract
   */
  event VaultCreated(
    address indexed admin,
    address indexed vault,
    address ownMevEscrow,
    bytes params
  );

  /**
   * @notice The address of the Vault implementation contract used for proxy creation
   * @return The address of the Vault implementation contract
   */
  function implementation() external view returns (address);

  /**
   * @notice The address of the own MEV escrow contract used for Vault creation
   * @return The address of the MEV escrow contract
   */
  function ownMevEscrow() external view returns (address);

  /**
   * @notice The address of the Vault admin used for Vault creation
   * @return The address of the Vault admin
   */
  function vaultAdmin() external view returns (address);

  /**
   * @notice Create Vault. Must transfer security deposit together with a call.
   * @param admin The address of the Vault admin
   * @param params The encoded parameters for initializing the Vault contract
   * @param isOwnMevEscrow Whether to deploy own escrow contract or connect to a smoothing pool for priority fees and MEV rewards
   * @return vault The address of the created Vault
   */
  function createVault(
    address admin,
    bytes calldata params,
    bool isOwnMevEscrow
  ) external payable returns (address vault);
}
