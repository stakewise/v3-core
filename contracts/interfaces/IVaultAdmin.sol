// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

/**
 * @title IVaultState
 * @author StakeWise
 * @notice Defines the interface for the VaultAdmin contract
 */
interface IVaultAdmin {
  /**
   * @notice Event emitted on metadata ipfs hash update
   * @param caller The address of the function caller
   * @param metadataIpfsHash The new metadata IPFS hash
   */
  event MetadataUpdated(address indexed caller, string metadataIpfsHash);

  /**
   * @notice The Vault admin
   * @return The address of the Vault admin
   */
  function admin() external view returns (address);

  /**
   * @notice Function for updating the metadata IPFS hash. Can only be called by Vault admin.
   * @param metadataIpfsHash The new metadata IPFS hash
   */
  function setMetadata(string calldata metadataIpfsHash) external;
}
