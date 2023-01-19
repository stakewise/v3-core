// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {MerkleProof} from '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import {IKeeperValidators} from '../../interfaces/IKeeperValidators.sol';
import {IVaultValidators} from '../../interfaces/IVaultValidators.sol';
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
  uint256 internal constant _validatorDeposit = 32 ether;
  uint256 internal constant _validatorLength = 176;

  /// @inheritdoc IVaultValidators
  bytes32 public override validatorsRoot;

  /// @inheritdoc IVaultValidators
  uint256 public override validatorIndex;

  /// @inheritdoc IVaultValidators
  function withdrawalCredentials() public view override returns (bytes memory) {
    return abi.encodePacked(bytes1(0x01), bytes11(0x0), address(this));
  }

  /// @inheritdoc IVaultValidators
  function registerValidator(
    IKeeperValidators.ApprovalParams calldata keeperParams,
    bytes32[] calldata proof
  ) external override {
    // get approval from oracles
    IKeeperValidators(keeper).approveValidators(keeperParams);

    // check enough available assets
    if (availableAssets() < _validatorDeposit) revert InsufficientAvailableAssets();

    // check validator length is valid
    if (keeperParams.validators.length != _validatorLength) revert InvalidValidator();

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
      revert InvalidProof();
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
    // get approval from oracles
    IKeeperValidators(keeper).approveValidators(keeperParams);

    // check enough available assets
    uint256 validatorsCount = keeperParams.validators.length / _validatorLength;
    if (availableAssets() < _validatorDeposit * validatorsCount) {
      revert InsufficientAvailableAssets();
    }

    // check validators length is valid
    unchecked {
      if (
        validatorsCount == 0 ||
        validatorsCount * _validatorLength != keeperParams.validators.length ||
        indexes.length != validatorsCount
      ) {
        revert InvalidValidators();
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
      revert InvalidProof();
    }

    // increment index for the next validator
    unchecked {
      // cannot realistically overflow
      validatorIndex += validatorsCount;
    }
  }

  /// @inheritdoc IVaultValidators
  function setValidatorsRoot(
    bytes32 _validatorsRoot,
    string calldata validatorsIpfsHash
  ) external override onlyAdmin {
    _setValidatorsRoot(_validatorsRoot, validatorsIpfsHash);
  }

  /**
   * @dev Internal function for updating the validators root externally or from the initializer
   * @param _validatorsRoot The new validators merkle tree root
   * @param validatorsIpfsHash The new IPFS hash with all the validators deposit data for the new root
   */
  function _setValidatorsRoot(bytes32 _validatorsRoot, string memory validatorsIpfsHash) internal {
    validatorsRoot = _validatorsRoot;
    // reset validator index on every root update
    validatorIndex = 0;
    emit ValidatorsRootUpdated(_validatorsRoot, validatorsIpfsHash);
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
   * @dev Initializes the VaultValidators contract
   * @param _validatorsRoot The validators merkle tree root
   * @param validatorsIpfsHash The IPFS hash with all the validators deposit data for the new root
   */
  function __VaultValidators_init(
    bytes32 _validatorsRoot,
    string memory validatorsIpfsHash
  ) internal onlyInitializing {
    _setValidatorsRoot(_validatorsRoot, validatorsIpfsHash);
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
