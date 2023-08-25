// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {IKeeperRewards} from './IKeeperRewards.sol';
import {IKeeperOracles} from './IKeeperOracles.sol';

/**
 * @title IKeeperValidators
 * @author StakeWise
 * @notice Defines the interface for the Keeper validators
 */
interface IKeeperValidators is IKeeperOracles, IKeeperRewards {
  /**
   * @notice Event emitted on validators approval
   * @param vault The address of the Vault
   * @param validators The concatenation of the validators' public key, signature and deposit data root
   * @param exitSignaturesIpfsHash The IPFS hash with the validators' exit signatures
   */
  event ValidatorsApproval(address indexed vault, bytes validators, string exitSignaturesIpfsHash);

  /**
   * @notice Event emitted on exit signatures update
   * @param caller The address of the function caller
   * @param vault The address of the Vault
   * @param nonce The nonce used for verifying Oracles' signatures
   * @param exitSignaturesIpfsHash The IPFS hash with the validators' exit signatures
   */
  event ExitSignaturesUpdated(
    address indexed caller,
    address indexed vault,
    uint256 nonce,
    string exitSignaturesIpfsHash
  );

  /**
   * @notice Event emitted on validators min oracles number update
   * @param oracles The new minimum number of oracles required to approve validators
   */
  event ValidatorsMinOraclesUpdated(uint256 oracles);

  /**
   * @notice Get nonce for the next vault exit signatures update
   * @param vault The address of the Vault to get the nonce for
   * @return The nonce of the Vault for updating signatures
   */
  function exitSignaturesNonces(address vault) external view returns (uint256);

  /**
   * @notice Struct for approving registration of one or more validators
   * @param validatorsRegistryRoot The deposit data root used to verify that oracles approved validators
   * @param deadline The deadline for submitting the approval
   * @param validators The concatenation of the validators' public key, signature and deposit data root
   * @param signatures The concatenation of Oracles' signatures
   * @param exitSignaturesIpfsHash The IPFS hash with the validators' exit signatures
   */
  struct ApprovalParams {
    bytes32 validatorsRegistryRoot;
    uint256 deadline;
    bytes validators;
    bytes signatures;
    string exitSignaturesIpfsHash;
  }

  /**
   * @notice The minimum number of oracles required to update validators
   * @return The minimum number of oracles
   */
  function validatorsMinOracles() external view returns (uint256);

  /**
   * @notice Function for approving validators registration
   * @param params The parameters for approving validators registration
   */
  function approveValidators(ApprovalParams calldata params) external;

  /**
   * @notice Function for updating exit signatures for every hard fork
   * @param vault The address of the Vault to update signatures for
   * @param deadline The deadline for submitting signatures update
   * @param exitSignaturesIpfsHash The IPFS hash with the validators' exit signatures
   * @param oraclesSignatures The concatenation of Oracles' signatures
   */
  function updateExitSignatures(
    address vault,
    uint256 deadline,
    string calldata exitSignaturesIpfsHash,
    bytes calldata oraclesSignatures
  ) external;

  /**
   * @notice Function for updating validators min oracles number
   * @param _validatorsMinOracles The new minimum number of oracles required to approve validators
   */
  function setValidatorsMinOracles(uint256 _validatorsMinOracles) external;
}
