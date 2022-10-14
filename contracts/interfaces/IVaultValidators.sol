// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {IFeesEscrow} from '../interfaces/IFeesEscrow.sol';

/**
 * @title IVaultValidators
 * @author StakeWise
 * @notice Defines the interface for the Vault Validators
 */
interface IVaultValidators {
  error InvalidValidator();
  error InvalidProofsLength();

  /**
   * @notice Event emitted on validators merkle tree root update
   * @param newValidatorsRoot The new validators merkle tree root
   * @param newValidatorsIpfsHash The new IPFS hash with all the validators deposit data
   */
  event ValidatorsRootUpdated(bytes32 indexed newValidatorsRoot, string newValidatorsIpfsHash);

  /**
   * @notice Event emitted on validator registration
   * @param publicKey The public key of the validator that was registered
   */
  event ValidatorRegistered(bytes publicKey);

  /**
   * @notice The contract that accumulates rewards received from priority fees and MEV
   * @return The fees escrow contract address
   */
  function feesEscrow() external view returns (IFeesEscrow);

  /**
   * @notice The Vault validators root
   * @return The Merkle Tree root to use for verifying validators deposit data
   */
  function validatorsRoot() external view returns (bytes32);

  /**
   * @notice Withdrawal Credentials
   * @return The credentials used for the validators withdrawals
   */
  function withdrawalCredentials() external view returns (bytes memory);

  /**
   * @notice Function for updating the validators Merkle Tree root. Can only be called by the operator.
   * @param newValidatorsRoot The new validators merkle tree root
   * @param newValidatorsIpfsHash The new IPFS hash with all the validators deposit data for the new root
   */
  function setValidatorsRoot(bytes32 newValidatorsRoot, string memory newValidatorsIpfsHash)
    external;

  /**
   * @notice Function for registering validator. Can only be called by the keeper.
   * @param validator The concatenation of the validator public key, signature and deposit data root
   * @param proof The proof used to verify that the validator is part of the validators Merkle Tree
   */
  function registerValidator(bytes calldata validator, bytes32[] calldata proof) external;

  /**
   * @notice Function for registering validators. Can only be called by the keeper.
   * @param validators The list of concatenations of the validators public keys, signatures and deposit data roots
   * @param proofs The list of proofs used to verify that the validators are part of the Merkle Tree
   */
  function registerValidators(bytes[] calldata validators, bytes32[][] calldata proofs) external;
}
