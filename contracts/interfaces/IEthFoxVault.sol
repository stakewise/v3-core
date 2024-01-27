// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

/**
 * @title IEthFoxVault
 * @author StakeWise
 * @notice Defines the interface for the EthFoxVault contract
 */
interface IEthFoxVault {
  /**
   * @dev Struct for initializing the EthVault contract
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
   * @notice Initializes the EthFoxVault contract. Must transfer security deposit together with a call.
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
