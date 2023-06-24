// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {IKeeperValidators} from './IKeeperValidators.sol';
import {IVaultAdmin} from './IVaultAdmin.sol';
import {IVaultState} from './IVaultState.sol';

/**
 * @title IVaultValidators
 * @author StakeWise
 * @notice Defines the interface for VaultValidators contract
 */
interface IVaultValidators is IVaultAdmin, IVaultState {
  /**
   * @notice Event emitted on validator registration
   * @param publicKey The public key of the validator that was registered
   */
  event ValidatorRegistered(bytes publicKey);

  /**
   * @notice Event emitted on keys manager address update
   * @param caller The address of the function caller
   * @param keysManager The address of the new keys manager
   */
  event KeysManagerUpdated(address indexed caller, address indexed keysManager);

  /**
   * @notice Event emitted on validators merkle tree root update
   * @param caller The address of the function caller
   * @param validatorsRoot The new validators merkle tree root
   */
  event ValidatorsRootUpdated(address indexed caller, bytes32 indexed validatorsRoot);

  /**
   * @notice The Vault keys manager address
   * @return The address that can update validators merkle tree root
   */
  function keysManager() external view returns (address);

  /**
   * @notice The Vault validators root
   * @return The merkle tree root to use for verifying validators deposit data
   */
  function validatorsRoot() external view returns (bytes32);

  /**
   * @notice The Vault validator index
   * @return The index of the next validator to be registered in the current deposit data file
   */
  function validatorIndex() external view returns (uint256);

  /**
   * @notice Function for registering single validator
   * @param keeperParams The parameters for getting approval from Keeper oracles
   * @param proof The proof used to verify that the validator is part of the validators merkle tree
   */
  function registerValidator(
    IKeeperValidators.ApprovalParams calldata keeperParams,
    bytes32[] calldata proof
  ) external;

  /**
   * @notice Function for registering multiple validators
   * @param keeperParams The parameters for getting approval from Keeper oracles
   * @param indexes The indexes of the leaves for the merkle tree multi proof verification
   * @param proofFlags The multi proof flags for the merkle tree verification
   * @param proof The proof used for the merkle tree verification
   */
  function registerValidators(
    IKeeperValidators.ApprovalParams calldata keeperParams,
    uint256[] calldata indexes,
    bool[] calldata proofFlags,
    bytes32[] calldata proof
  ) external;

  /**
   * @notice Function for updating the keys manager. Can only be called by the admin.
   * @param _keysManager The new keys manager address
   */
  function setKeysManager(address _keysManager) external;

  /**
   * @notice Function for updating the validators merkle tree root. Can only be called by the keys manager.
   * @param _validatorsRoot The new validators merkle tree root
   */
  function setValidatorsRoot(bytes32 _validatorsRoot) external;
}
