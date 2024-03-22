// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {IKeeperValidators} from './IKeeperValidators.sol';

/**
 * @title IDepositDataManager
 * @author StakeWise
 * @notice Defines the interface for DepositDataManager
 */
interface IDepositDataManager {
  /**
   * @notice Event emitted on deposit data manager update
   * @param vault The address of the vault
   * @param depositDataManager The address of the new deposit data manager
   */
  event DepositDataManagerUpdated(address indexed vault, address depositDataManager);

  /**
   * @notice Event emitted on deposit data root update
   * @param vault The address of the vault
   * @param depositDataRoot The new deposit data Merkle tree root
   */
  event DepositDataRootUpdated(address indexed vault, bytes32 depositDataRoot);

  /**
   * @notice Event emitted on deposit data migration
   * @param vault The address of the vault
   * @param depositDataRoot The deposit data root
   * @param validatorIndex The index of the next validator to be registered
   * @param depositDataManager The address of the deposit data manager
   */
  event DepositDataMigrated(
    address indexed vault,
    bytes32 depositDataRoot,
    uint256 validatorIndex,
    address depositDataManager
  );

  /**
   * @notice The vault deposit data index
   * @param vault The address of the vault
   * @return validatorIndex The index of the next validator to be registered
   */
  function depositDataIndexes(address vault) external view returns (uint256 validatorIndex);

  /**
   * @notice The vault deposit data root
   * @param vault The address of the vault
   * @return depositDataRoot The deposit data root
   */
  function depositDataRoots(address vault) external view returns (bytes32 depositDataRoot);

  /**
   * @notice The vault deposit data manager. Defaults to the vault admin if not set.
   * @param vault The address of the vault
   * @return depositDataManager The address of the deposit data manager
   */
  function getDepositDataManager(address vault) external view returns (address);

  /**
   * @notice Function for setting the deposit data manager for the vault. Can only be called by the vault admin.
   * @param vault The address of the vault
   * @param depositDataManager The address of the new deposit data manager
   */
  function setDepositDataManager(address vault, address depositDataManager) external;

  /**
   * @notice Function for setting the deposit data root for the vault. Can only be called by the deposit data manager.
   * @param vault The address of the vault
   * @param depositDataRoot The new deposit data Merkle tree root
   */
  function setDepositDataRoot(address vault, bytes32 depositDataRoot) external;

  /**
   * @notice Function for registering single validator
   * @param vault The address of the vault
   * @param keeperParams The parameters for getting approval from Keeper oracles
   * @param proof The proof used to verify that the validator is part of the deposit data merkle tree
   */
  function registerValidator(
    address vault,
    IKeeperValidators.ApprovalParams calldata keeperParams,
    bytes32[] calldata proof
  ) external;

  /**
   * @notice Function for registering multiple validators
   * @param vault The address of the vault
   * @param keeperParams The parameters for getting approval from Keeper oracles
   * @param indexes The indexes of the leaves for the merkle tree multi proof verification
   * @param proofFlags The multi proof flags for the merkle tree verification
   * @param proof The proof used for the merkle tree verification
   */
  function registerValidators(
    address vault,
    IKeeperValidators.ApprovalParams calldata keeperParams,
    uint256[] calldata indexes,
    bool[] calldata proofFlags,
    bytes32[] calldata proof
  ) external;

  /**
   * @notice Function for migrating the deposit data of the Vault. Can only be called once by a vault during an upgrade.
   * @param depositDataRoot The current deposit data root
   * @param validatorIndex The current index of the next validator to be registered
   * @param depositDataManager The address of the deposit data manager
   */
  function migrate(
    bytes32 depositDataRoot,
    uint256 validatorIndex,
    address depositDataManager
  ) external;
}
