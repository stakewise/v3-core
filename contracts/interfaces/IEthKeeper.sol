// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {IOracles} from './IOracles.sol';
import {IValidatorsRegistry} from './IValidatorsRegistry.sol';
import {IBaseKeeper} from './IBaseKeeper.sol';

/**
 * @title IEthKeeper
 * @author StakeWise
 * @notice Defines the interface for the EthKeeper contract
 */
interface IEthKeeper is IBaseKeeper {
  /**
   * @notice Struct for registering single validator
   * @param vault The address of the vault
   * @param validatorsRegistryRoot The deposit data root used to verify that oracles approved validator registration
   * @param validator The concatenation of the validator public key, signature and deposit data root
   * @param signatures The concatenation of Oracles' signatures
   * @param exitSignatureIpfsHash The IPFS hash with the validator's exit signature
   * @param proof The proof used to verify that the validator is part of the validators Merkle Tree
   */
  struct ValidatorRegistrationData {
    address vault;
    bytes32 validatorsRegistryRoot;
    bytes validator;
    bytes signatures;
    string exitSignatureIpfsHash;
    bytes32[] proof;
  }

  /**
   * @notice Struct for registering multiple validators
   * @param vault The address of the vault
   * @param validatorsRegistryRoot The deposit data root used to verify that oracles approved validators registration
   * @param validators The concatenation of the validators' public key, signature and deposit data root
   * @param signatures The concatenation of Oracles' signatures
   * @param exitSignaturesIpfsHash The IPFS hash with the validators' exit signature
   * @param indexes The indexes of the validators for the proof verification
   * @param proofFlags The multi proof flags for the validators Merkle Tree verification
   * @param proof The multi proof used for the validators Merkle Tree verification
   */
  struct ValidatorsRegistrationData {
    address vault;
    bytes32 validatorsRegistryRoot;
    bytes validators;
    bytes signatures;
    string exitSignaturesIpfsHash;
    uint256[] indexes;
    bool[] proofFlags;
    bytes32[] proof;
  }

  /**
   * @notice Event emitted on validators registration
   * @param vault The address of the Vault
   * @param validators The validators registered
   * @param exitSignaturesIpfsHash The IPFS hash with the validators' exit signatures
   * @param timestamp The validators registration timestamp
   */
  event ValidatorsRegistered(
    address indexed vault,
    bytes validators,
    string exitSignaturesIpfsHash,
    uint256 timestamp
  );

  /**
   * @notice Validators Registry Address
   * @return The address of the Validators Registry contract
   */
  function validatorsRegistry() external view returns (IValidatorsRegistry);

  /**
   * @dev Initializes the EthKeeper contract
   * @param _owner The address of the EthKeeper owner
   */
  function initialize(address _owner) external;

  /**
   * @notice Function for registering single validator
   * @param data The data for registering single validator
   */
  function registerValidator(ValidatorRegistrationData calldata data) external;

  /**
   * @notice Function for registering multiple validators in one call
   * @param data The data for registering multiple validators
   */
  function registerValidators(ValidatorsRegistrationData calldata data) external;
}
