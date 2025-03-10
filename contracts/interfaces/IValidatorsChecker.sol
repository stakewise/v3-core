// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

/**
 * @title IValidatorsChecker
 * @author StakeWise
 * @notice Defines the interface for ValidatorsChecker
 */
interface IValidatorsChecker {
  enum Status {
    SUCCEEDED,
    INVALID_VALIDATORS_REGISTRY_ROOT,
    INVALID_VAULT,
    INSUFFICIENT_ASSETS,
    INVALID_SIGNATURE,
    INVALID_VALIDATORS_MANAGER,
    INVALID_VALIDATORS_COUNT,
    INVALID_VALIDATORS_LENGTH,
    INVALID_PROOF
  }

  /**
   * @notice Function for checking validators manager signature
   * @param vault The address of the vault
   * @param validatorsRegistryRoot The validators registry root
   * @param validators The concatenation of the validators' public key, deposit signature, deposit root and optionally withdrawal address
   * @param signature The validators manager signature
   * @return blockNumber Current block number
   * @return status The status of the verification
   */
  function checkValidatorsManagerSignature(
    address vault,
    bytes32 validatorsRegistryRoot,
    bytes calldata validators,
    bytes calldata signature
  ) external view returns (uint256 blockNumber, Status status);

  /**
   * @notice Function for checking deposit data root
   * @param vault The address of the vault
   * @param validatorsRegistryRoot The validators registry root
   * @param validators The concatenation of the validators' public key, deposit signature, deposit root and optionally withdrawal address
   * @param proof The proof used for the merkle tree verification
   * @param proofFlags The multi proof flags for the merkle tree verification
   * @param proofIndexes The indexes of the leaves for the merkle tree multi proof verification
   * @return blockNumber Current block number
   * @return status The status of the verification
   */
  function checkDepositDataRoot(
    address vault,
    bytes32 validatorsRegistryRoot,
    bytes calldata validators,
    bytes32[] calldata proof,
    bool[] calldata proofFlags,
    uint256[] calldata proofIndexes
  ) external view returns (uint256 blockNumber, Status status);
}
