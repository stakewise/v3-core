// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.18;

import {IValidatorsRegistry} from './IValidatorsRegistry.sol';

/**
 * @title IKeeperValidators
 * @author StakeWise
 * @notice Defines the interface for the Keeper validators
 */
interface IKeeperValidators {
  // Custom errors
  error InvalidValidatorsRegistryRoot();

  /**
   * @notice Event emitted on validators approval
   * @param vault The address of the Vault
   * @param validators The concatenation of the validators' public key, signature and deposit data root
   * @param exitSignaturesIpfsHash The IPFS hash with the validators' exit signatures
   * @param updateTimestamp The update timestamp used for rewards calculation
   */
  event ValidatorsApproval(
    address indexed vault,
    bytes validators,
    string exitSignaturesIpfsHash,
    uint256 updateTimestamp
  );

  /**
   * @notice Validators Registry Address
   * @return The address of the beacon chain validators registry contract
   */
  function validatorsRegistry() external view returns (IValidatorsRegistry);

  /**
   * @notice Struct for approving registration of one or more validators
   * @param validatorsRegistryRoot The deposit data root used to verify that oracles approved validators
   * @param validators The concatenation of the validators' public key, signature and deposit data root
   * @param signatures The concatenation of Oracles' signatures
   * @param exitSignaturesIpfsHash The IPFS hash with the validators' exit signatures
   */
  struct ApprovalParams {
    bytes32 validatorsRegistryRoot;
    bytes validators;
    bytes signatures;
    string exitSignaturesIpfsHash;
  }

  /**
   * @notice Function for approving validators registration
   * @param params The parameters for approving validators registration
   */
  function approveValidators(ApprovalParams calldata params) external;
}
