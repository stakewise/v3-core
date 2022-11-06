// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {IOracles} from './IOracles.sol';
import {IValidatorsRegistry} from './IValidatorsRegistry.sol';
import {IKeeper} from './IKeeper.sol';

/**
 * @title IEthKeeper
 * @author StakeWise
 * @notice Defines the interface for the EthKeeper contract
 */
interface IEthKeeper is IKeeper {
  /**
   * @notice Event emitted on validators registration
   * @param vault The address of the Vault
   * @param validatorsRegistryRoot The deposit data root used to verify that oracles approved validator registration
   * @param validators The validators registered
   * @param signatures The Oracles signatures
   * @param timestamp The validators registration timestamp
   */
  event ValidatorsRegistered(
    address indexed vault,
    bytes32 indexed validatorsRegistryRoot,
    bytes validators,
    bytes signatures,
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
   * @param vault The address of the vault
   * @param validatorsRegistryRoot The deposit data root used to verify that oracles approved validator registration
   * @param validator The concatenation of the validator public key, signature and deposit data root
   * @param signatures The concatenation of Oracles' signatures
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
   * @param validatorsRegistryRoot The deposit data root used to verify that oracles approved validators registration
   * @param validators The concatenation of the validators' public key, signature and deposit data root
   * @param signatures The concatenation of Oracles' signatures
   * @param proofFlags The multi proof flags for the validators Merkle Tree verification
   * @param proof The multi proof used for the validators Merkle Tree verification
   */
  function registerValidators(
    address vault,
    bytes32 validatorsRegistryRoot,
    bytes calldata validators,
    bytes calldata signatures,
    bool[] calldata proofFlags,
    bytes32[] calldata proof
  ) external;
}
