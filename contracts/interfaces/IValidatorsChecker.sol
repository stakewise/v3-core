// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IKeeperRewards} from '../interfaces/IKeeperRewards.sol';
import {IMulticall} from './IMulticall.sol';

/**
 * @title IValidatorsChecker
 * @author StakeWise
 * @notice Defines the interface for ValidatorsChecker
 */
interface IValidatorsChecker is IMulticall {
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
   * @dev Struct for checking deposit data root
   * @param vault The address of the vault
   * @param validatorsRegistryRoot The validators registry root
   * @param validators The concatenation of the validators' public key, deposit signature, deposit root
   * @param proof The proof of the deposit data root
   * @param proofFlags The flags of the proof
   * @param proofIndexes The indexes of the proof
   */
  struct DepositDataRootCheckParams {
    address vault;
    bytes32 validatorsRegistryRoot;
    bytes validators;
    bytes32[] proof;
    bool[] proofFlags;
    uint256[] proofIndexes;
  }

  /**
   * @notice Function for updating vault state
   * @param vault The address of the vault
   * @param harvestParams The parameters for harvesting
   */
  function updateVaultState(
    address vault,
    IKeeperRewards.HarvestParams calldata harvestParams
  ) external;

  /**
   * @notice Function for getting the exit queue cumulative tickets
   * @param vault The address of the vault
   * @return The exit queue cumulative tickets
   */
  function getExitQueueCumulativeTickets(address vault) external view returns (uint256);

  /**
   * @notice Function for getting the exit queue missing assets
   * @param vault The address of the vault
   * @param withdrawingAssets The amount of assets currently being withdrawn from validators
   * @param targetCumulativeTickets The target cumulative tickets
   * @return missingAssets The exit queue missing assets
   */
  function getExitQueueMissingAssets(
    address vault,
    uint256 withdrawingAssets,
    uint256 targetCumulativeTickets
  ) external view returns (uint256 missingAssets);

  /**
   * @notice Function for checking validators manager signature
   * @param vault The address of the vault
   * @param validatorsRegistryRoot The validators registry root
   * @param validators The concatenation of the validators' public key, deposit signature, deposit root
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
   * @param params The parameters for checking deposit data root
   * @return blockNumber Current block number
   * @return status The status of the verification
   */
  function checkDepositDataRoot(
    DepositDataRootCheckParams calldata params
  ) external view returns (uint256 blockNumber, Status status);
}
