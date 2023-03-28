// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {IVaultAdmin} from './IVaultAdmin.sol';

/**
 * @title IVaultWhitelist
 * @author StakeWise
 * @notice Defines the interface for the VaultWhitelist contract
 */
interface IVaultWhitelist is IVaultAdmin {
  /// Custom errors
  error InvalidWhitelistProof();
  error WhitelistAlreadyUpdated();

  /**
   * @notice Event emitted on whitelist update
   * @param caller The address of the function caller
   * @param account The address of the account updated
   * @param approved Whether account is approved or not
   */
  event WhitelistUpdated(address indexed caller, address indexed account, bool approved);

  /**
   * @notice Event emitted when whitelister address is updated
   * @param caller The address of the function caller
   * @param whitelister The address of the new whitelister
   */
  event WhitelisterUpdated(address indexed caller, address indexed whitelister);

  /**
   * @notice Event emitted when whitelist Merkle tree root is updated
   * @param caller The address of the function caller
   * @param root The root of the Merkle tree
   * @param whitelistIpfsHash The IPFS hash with all the whitelisted accounts
   */
  event WhitelistRootUpdated(
    address indexed caller,
    bytes32 indexed root,
    string whitelistIpfsHash
  );

  /**
   * @notice Whitelister address
   * @return The address of the whitelister
   */
  function whitelister() external view returns (address);

  /**
   * @notice Whitelist root
   * @return The current Merkle tree root of the whitelist
   */
  function whitelistRoot() external view returns (bytes32);

  /**
   * @notice Checks whether account is whitelisted or not
   * @param account The account to check
   * @return `true` for the whitelisted account, `false` otherwise
   */
  function whitelistedAccounts(address account) external view returns (bool);

  /**
   * @notice Add or remove account from the whitelist. Can only be called by the whitelister.
   * @param account The account to add or remove from the whitelist
   * @param approved Whether account should be whitelisted or not
   */
  function updateWhitelist(address account, bool approved) external;

  /**
   * @notice Used to join whitelist using the whitelisted accounts tree proof
   * @dev Note that to remove the account from the whitelist, the new Merkle tree must be generated.
          Otherwise, the account will be able to re-join.
   * @param account The account to add to the list
   * @param proof The proof used to verify that account is part of the merkle tree
   */
  function joinWhitelist(address account, bytes32[] calldata proof) external;

  /**
   * @notice Used to update root of of the merkle tree with all the whitelisted accounts
   * @dev Note that to remove the account from the whitelist, the root must be updated.
          Otherwise, the account will be able to re-join.
   * @param _whitelistRoot The root of the Merkle tree
   * @param whitelistIpfsHash The IPFS hash with all the whitelisted accounts
   */
  function setWhitelistRoot(bytes32 _whitelistRoot, string calldata whitelistIpfsHash) external;

  /**
   * @notice Used to update the whitelister. Can only be called by the Vault admin.
   * @param _whitelister The address of the new whitelister
   */
  function setWhitelister(address _whitelister) external;
}
