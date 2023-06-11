// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {MerkleProof} from '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import {IKeeperValidators} from '../../interfaces/IKeeperValidators.sol';
import {IVaultValidators} from '../../interfaces/IVaultValidators.sol';
import {Errors} from '../../libraries/Errors.sol';
import {VaultImmutables} from './VaultImmutables.sol';
import {VaultAdmin} from './VaultAdmin.sol';
import {VaultState} from './VaultState.sol';

/**
 * @title VaultValidators
 * @author StakeWise
 * @notice Defines the validators functionality for the Vault
 */
abstract contract VaultValidators is
  VaultImmutables,
  Initializable,
  VaultAdmin,
  VaultState,
  IVaultValidators
{
  uint256 internal constant _validatorLength = 176;

  /// @inheritdoc IVaultValidators
  bytes32 public override validatorsRoot;

  /// @inheritdoc IVaultValidators
  uint256 public override validatorIndex;

  address private _keysManager;

  /// @inheritdoc IVaultValidators
  function keysManager() public view override returns (address) {
    // SLOAD to memory
    address keysManager_ = _keysManager;
    // if keysManager is not set, use admin address
    return keysManager_ == address(0) ? admin : keysManager_;
  }

  /// @inheritdoc IVaultValidators
  function registerValidator(
    IKeeperValidators.ApprovalParams calldata keeperParams,
    bytes32[] calldata proof
  ) external override {
    _checkHarvested();

    // get approval from oracles
    IKeeperValidators(_keeper).approveValidators(keeperParams);

    // check enough withdrawable assets
    if (withdrawableAssets() < _validatorDeposit()) revert Errors.InsufficientAssets();

    // check validator length is valid
    if (keeperParams.validators.length != _validatorLength) revert Errors.InvalidValidator();

    // SLOAD to memory
    uint256 currentIndex = validatorIndex;

    // check matches merkle root and next validator index
    if (
      !MerkleProof.verifyCalldata(
        proof,
        validatorsRoot,
        keccak256(bytes.concat(keccak256(abi.encode(keeperParams.validators, currentIndex))))
      )
    ) {
      revert Errors.InvalidProof();
    }

    // register validator
    _registerSingleValidator(keeperParams.validators);

    // increment index for the next validator
    unchecked {
      // cannot realistically overflow
      validatorIndex = currentIndex + 1;
    }
  }

  /// @inheritdoc IVaultValidators
  function registerValidators(
    IKeeperValidators.ApprovalParams calldata keeperParams,
    uint256[] calldata indexes,
    bool[] calldata proofFlags,
    bytes32[] calldata proof
  ) external override {
    _checkHarvested();

    // get approval from oracles
    IKeeperValidators(_keeper).approveValidators(keeperParams);

    // check enough withdrawable assets
    uint256 validatorsCount = keeperParams.validators.length / _validatorLength;
    if (withdrawableAssets() < _validatorDeposit() * validatorsCount) {
      revert Errors.InsufficientAssets();
    }

    // check validators length is valid
    unchecked {
      if (
        validatorsCount == 0 ||
        validatorsCount * _validatorLength != keeperParams.validators.length ||
        indexes.length != validatorsCount
      ) {
        revert Errors.InvalidValidators();
      }
    }

    // check matches merkle root and next validator index
    if (
      !MerkleProof.multiProofVerifyCalldata(
        proof,
        proofFlags,
        validatorsRoot,
        _registerMultipleValidators(keeperParams.validators, indexes)
      )
    ) {
      revert Errors.InvalidProof();
    }

    // increment index for the next validator
    unchecked {
      // cannot realistically overflow
      validatorIndex += validatorsCount;
    }
  }

  /// @inheritdoc IVaultValidators
  function setKeysManager(address keysManager_) external override {
    _checkAdmin();
    if (keysManager_ == address(0)) revert Errors.ZeroAddress();
    // update keysManager address
    _keysManager = keysManager_;
    emit KeysManagerUpdated(msg.sender, keysManager_);
  }

  /// @inheritdoc IVaultValidators
  function setValidatorsRoot(bytes32 _validatorsRoot) external override {
    if (msg.sender != keysManager()) revert Errors.AccessDenied();
    _setValidatorsRoot(_validatorsRoot);
  }

  /**
   * @dev Internal function for updating the validators root externally or from the initializer
   * @param _validatorsRoot The new validators merkle tree root
   */
  function _setValidatorsRoot(bytes32 _validatorsRoot) private {
    validatorsRoot = _validatorsRoot;
    // reset validator index on every root update
    validatorIndex = 0;
    emit ValidatorsRootUpdated(msg.sender, _validatorsRoot);
  }

  /**
   * @dev Internal function for calculating Vault withdrawal credentials
   * @return The credentials used for the validators withdrawals
   */
  function _withdrawalCredentials() internal view returns (bytes memory) {
    return abi.encodePacked(bytes1(0x01), bytes11(0x0), address(this));
  }

  /**
   * @dev Internal function for registering single validator. Must emit ValidatorRegistered event.
   * @param validator The concatenation of the validator public key, signature and deposit data root
   */
  function _registerSingleValidator(bytes calldata validator) internal virtual;

  /**
   * @dev Internal function for registering multiple validators. Must emit ValidatorRegistered event for every validator.
   * @param validators The concatenation of the validators' public key, signature and deposit data root
   * @param indexes The indexes of the leaves for the merkle tree multi proof verification
   * @return leaves The leaves used for the merkle tree multi proof verification
   */
  function _registerMultipleValidators(
    bytes calldata validators,
    uint256[] calldata indexes
  ) internal virtual returns (bytes32[] memory leaves);

  /**
   * @dev Internal function for fetching validator deposit amount
   */
  function _validatorDeposit() internal pure virtual returns (uint256);

  /**
   * @dev Initializes the VaultValidators contract
   * @dev NB! This initializer must be called after VaultState initializer
   */
  function __VaultValidators_init() internal view onlyInitializing {
    if (capacity() < _validatorDeposit()) revert Errors.InvalidCapacity();
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
