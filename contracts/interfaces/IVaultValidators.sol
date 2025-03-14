// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

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
   * @notice Event emitted on V1 validator registration
   * @param publicKey The public key of the validator that was registered
   */
  event ValidatorRegistered(bytes publicKey);

  /**
   * @notice Event emitted on V2 validator registration
   * @param publicKey The public key of the validator that was registered
   * @param amount The amount of assets that was registered
   */
  event ValidatorRegistered(bytes publicKey, uint256 amount);

  /**
   * @notice Event emitted on validator withdrawal
   * @param publicKey The public key of the validator that was withdrawn
   * @param amount The amount of assets that was withdrawn
   * @param feePaid The amount of fee that was paid
   */
  event ValidatorWithdrawn(bytes publicKey, uint256 amount, uint256 feePaid);

  /**
   * @notice Event emitted on validator balance top-up
   * @param publicKey The public key of the validator that was funded
   * @param amount The amount of assets that was funded
   */
  event ValidatorFunded(bytes publicKey, uint256 amount);

  /**
   * @notice Event emitted on validators consolidation
   * @param fromPublicKey The public key of the validator that was consolidated
   * @param toPublicKey The public key of the validator that was consolidated to
   * @param feePaid The amount of fee that was paid
   */
  event ValidatorConsolidated(bytes fromPublicKey, bytes toPublicKey, uint256 feePaid);

  /**
   * @notice Event emitted on keys manager address update (deprecated)
   * @param caller The address of the function caller
   * @param keysManager The address of the new keys manager
   */
  event KeysManagerUpdated(address indexed caller, address indexed keysManager);

  /**
   * @notice Event emitted on validators merkle tree root update (deprecated)
   * @param caller The address of the function caller
   * @param validatorsRoot The new validators merkle tree root
   */
  event ValidatorsRootUpdated(address indexed caller, bytes32 indexed validatorsRoot);

  /**
   * @notice Event emitted on validators manager address update
   * @param caller The address of the function caller
   * @param validatorsManager The address of the new validators manager
   */
  event ValidatorsManagerUpdated(address indexed caller, address indexed validatorsManager);

  /**
   * @notice The Vault validators manager address
   * @return The address that can register validators
   */
  function validatorsManager() external view returns (address);

  /**
   * @notice The nonce for the validators manager used for signing
   * @return The nonce for the validators manager
   */
  function validatorsManagerNonce() external view returns (uint256);

  /**
   * @notice Function for checking if the validator is tracked in the contract
   * @param publicKeyHash The keccak256 hash of the public key of the validator
   * @return Whether the validator is tracked
   */
  function trackedValidators(bytes32 publicKeyHash) external view returns (bool);

  /**
   * @notice Function for funding single or multiple existing validators
   * @param validators The concatenated validators data
   * @param validatorsManagerSignature The optional signature from the validators manager
   */
  function fundValidators(
    bytes calldata validators,
    bytes calldata validatorsManagerSignature
  ) external;

  /**
   * @notice Function for withdrawing single or multiple validators
   * @param validators The concatenated validators data
   * @param validatorsManagerSignature The optional signature from the validators manager
   */
  function withdrawValidators(
    bytes calldata validators,
    bytes calldata validatorsManagerSignature
  ) external payable;

  /**
   * @notice Function for consolidating single or multiple validators
   * @param validators The concatenated validators data
   * @param validatorsManagerSignature The optional signature from the validators manager
   * @param oracleSignatures The optional signatures from the oracles
   */
  function consolidateValidators(
    bytes calldata validators,
    bytes calldata validatorsManagerSignature,
    bytes calldata oracleSignatures
  ) external payable;

  /**
   * @notice Function for registering single or multiple validators
   * @param keeperParams The parameters for getting approval from Keeper oracles
   * @param validatorsManagerSignature The optional signature from the validators manager
   */
  function registerValidators(
    IKeeperValidators.ApprovalParams calldata keeperParams,
    bytes calldata validatorsManagerSignature
  ) external;

  /**
   * @notice Function for updating the validators manager. Can only be called by the admin. Default is the DepositDataRegistry contract.
   * @param _validatorsManager The new validators manager address
   */
  function setValidatorsManager(address _validatorsManager) external;
}
