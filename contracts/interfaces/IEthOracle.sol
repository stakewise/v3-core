// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {ISigners} from './ISigners.sol';
import {IOracle} from './IOracle.sol';

/**
 * @title IEthOracle
 * @author StakeWise
 * @notice Defines the interface for the EthOracle contract
 */
interface IEthOracle is IOracle {
  /**
   * @notice Event emitted on single validator registration
   * @param vault The address of the Vault
   * @param validatorsRegistryRoot The deposit data root used to verify that signers approved validator registration
   * @param validator The validator registered
   * @param signatures The Signers signatures
   */
  event ValidatorRegistered(
    address indexed vault,
    bytes32 indexed validatorsRegistryRoot,
    bytes validator,
    bytes signatures
  );

  /**
   * @notice Event emitted on multiple validators registration
   * @param vault The address of the Vault
   * @param validatorsRegistryRoot The deposit data root used to verify that signers approved validator registration
   * @param validators The validators registered
   * @param signatures The Signers signatures
   */
  event ValidatorsRegistered(
    address indexed vault,
    bytes32 indexed validatorsRegistryRoot,
    bytes[] validators,
    bytes signatures
  );

  /**
   * @dev Initializes the EthOracle contract
   * @param _owner The address of the EthOracle owner
   */
  function initialize(address _owner) external;

  /**
   * @notice Function for registering single validator
   * @param vault The address of the vault
   * @param validatorsRegistryRoot The deposit data root used to verify that signers approved validator registration
   * @param validator The concatenation of the validator public key, signature and deposit data root
   * @param signatures The concatenation of Signers' signatures
   * @param proof The proof used to verify that the validator is part of the validators Merkle Tree
   */
  function registerValidator(
    address vault,
    bytes32 validatorsRegistryRoot,
    bytes calldata validator,
    bytes calldata signatures,
    bytes32[] calldata proof
  ) external;

  /**
   * @notice Function for registering multiple validators in one call
   * @param vault The address of the vault
   * @param validatorsRegistryRoot The deposit data root used to verify that signers approved validators registration
   * @param validators The list of concatenations of the validators' public key, signature and deposit data root
   * @param signatures The concatenation of Signers' signatures
   * @param proofFlags The multi proof flags for the validators Merkle Tree verification
   * @param proof The multi proof used for the validators Merkle Tree verification
   */
  function registerValidators(
    address vault,
    bytes32 validatorsRegistryRoot,
    bytes[] calldata validators,
    bytes calldata signatures,
    bool[] calldata proofFlags,
    bytes32[] calldata proof
  ) external;
}
