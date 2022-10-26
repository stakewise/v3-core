// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

/**
 * @title ISigners
 * @author StakeWise
 * @notice Defines the interface for the Signers contract
 */
interface ISigners {
  // Custom errors
  error NotEnoughSignatures();
  error InvalidSigner();
  error AlreadyAdded();
  error AlreadyRemoved();
  error InvalidRequiredSigners();

  /**
   * @notice Event emitted on the signer addition
   * @param signer The address of the added signer
   */
  event SignerAdded(address indexed signer);

  /**
   * @notice Event emitted on the signer removal
   * @param signer The address of the removed signer
   */
  event SignerRemoved(address indexed signer);

  /**
   * @notice Event emitted on the required signers number update
   * @param requiredSigners The new number of required signers
   */
  event RequiredSignersUpdated(uint256 requiredSigners);

  /**
   * @notice Function for verifying whether signer is registered or not
   * @param signer The address of the signer to check
   * @return `true` for the registered signer, `false` otherwise
   */
  function isSigner(address signer) external view returns (bool);

  /**
   * @notice Total Signers
   * @return The total number of signers registered
   */
  function totalSigners() external view returns (uint256);

  /**
   * @notice Required Signers
   * @return The required number of signers to pass the verification
   */
  function requiredSigners() external view returns (uint256);

  /**
   * @notice Function for adding signer to the set
   * @param signer The address of the signer to add
   */
  function addSigner(address signer) external;

  /**
   * @notice Function for removing signer from the set. At least one signer must be preserved.
   * @param signer The address of the signer to remove
   */
  function removeSigner(address signer) external;

  /**
   * @notice Function for updating the required number of signatures to pass the verification
   * @param _requiredSigners The new number of required signatures. Cannot be zero or larger than total signers.
   */
  function setRequiredSigners(uint256 _requiredSigners) external;

  /**
   * @notice Function for verifying whether enough signers have signed the message
   * @param message The message that was signed
   * @param signatures The concatenation of the signers' signatures
   */
  function verifySignatures(bytes32 message, bytes calldata signatures) external view;
}
