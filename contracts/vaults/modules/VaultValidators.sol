// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {MerkleProof} from '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
import {SignatureChecker} from '@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol';
import {IKeeperValidators} from '../../interfaces/IKeeperValidators.sol';
import {IDepositDataRegistry} from '../../interfaces/IDepositDataRegistry.sol';
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
  bytes32 private constant _registerValidatorsTypeHash =
    keccak256('VaultValidators(bytes32 validatorsRegistryRoot,bytes validators)');

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address private immutable _depositDataRegistry;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  uint256 private immutable _initialChainId;

  /// deprecated. Deposit data management is moved to DepositDataRegistry contract
  bytes32 private _validatorsRoot;

  /// deprecated. Deposit data management is moved to DepositDataRegistry contract
  uint256 private _validatorIndex;

  address private _validatorsManager;

  bytes32 private _initialDomainSeparator;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param depositDataRegistry The address of the DepositDataRegistry contract
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(address depositDataRegistry) {
    _depositDataRegistry = depositDataRegistry;
    _initialChainId = block.chainid;
  }

  /// @inheritdoc IVaultValidators
  function validatorsManager() public view override returns (address) {
    // SLOAD to memory
    address validatorsManager_ = _validatorsManager;
    // if validatorsManager is not set, use DepositDataRegistry contract address
    return validatorsManager_ == address(0) ? _depositDataRegistry : validatorsManager_;
  }

  /// @inheritdoc IVaultValidators
  function registerValidators(
    IKeeperValidators.ApprovalParams calldata keeperParams,
    bytes calldata validatorsManagerSignature
  ) external override {
    // get approval from oracles
    IKeeperValidators(_keeper).approveValidators(keeperParams);

    // check vault is up to date
    _checkHarvested();

    // check access
    address validatorsManager_ = validatorsManager();
    if (
      msg.sender != validatorsManager_ &&
      !SignatureChecker.isValidSignatureNow(
        validatorsManager_,
        _getSignedMessageHash(keeperParams),
        validatorsManagerSignature
      )
    ) {
      revert Errors.AccessDenied();
    }

    // check validators length is valid
    uint256 validatorLength = _validatorLength();
    uint256 validatorsCount = keeperParams.validators.length / validatorLength;
    unchecked {
      if (
        validatorsCount == 0 || validatorsCount * validatorLength != keeperParams.validators.length
      ) {
        revert Errors.InvalidValidators();
      }
    }

    // check enough withdrawable assets
    if (withdrawableAssets() < _validatorDeposit() * validatorsCount) {
      revert Errors.InsufficientAssets();
    }

    if (keeperParams.validators.length == validatorLength) {
      // register single validator
      _registerSingleValidator(keeperParams.validators);
    } else {
      // register multiple validators
      _registerMultipleValidators(keeperParams.validators);
    }
  }

  /// @inheritdoc IVaultValidators
  function setValidatorsManager(address validatorsManager_) external override {
    _checkAdmin();
    // update validatorsManager address
    _validatorsManager = validatorsManager_;
    emit ValidatorsManagerUpdated(msg.sender, validatorsManager_);
  }

  /**
   * @dev Internal function for registering validator. Must emit ValidatorRegistered event.
   * @param validator The validator registration data
   */
  function _registerSingleValidator(bytes calldata validator) internal virtual;

  /**
   * @dev Internal function for registering multiple validators. Must emit ValidatorRegistered event for every validator.
   * @param validators The validators registration data
   */
  function _registerMultipleValidators(bytes calldata validators) internal virtual;

  /**
   * @dev Internal function for defining the length of the validator data
   * @return The length of the single validator data
   */
  function _validatorLength() internal pure virtual returns (uint256);

  /**
   * @dev Internal function for fetching validator deposit amount
   */
  function _validatorDeposit() internal pure virtual returns (uint256);

  /**
   * @dev Initializes the VaultValidators contract
   * @dev NB! This initializer must be called after VaultState initializer
   */
  function __VaultValidators_init() internal onlyInitializing {
    if (capacity() < _validatorDeposit()) revert Errors.InvalidCapacity();
    // initialize domain separator
    _initialDomainSeparator = _computeVaultValidatorsDomain();
  }

  /**
   * @notice Get the hash to be signed by the validators manager
   * @param keeperParams The keeper approval parameters
   * @return The hash to be signed
   */
  function _getSignedMessageHash(
    IKeeperValidators.ApprovalParams calldata keeperParams
  ) private view returns (bytes32) {
    bytes32 domainSeparator = block.chainid == _initialChainId
      ? _initialDomainSeparator
      : _computeVaultValidatorsDomain();

    return
      MessageHashUtils.toTypedDataHash(
        domainSeparator,
        keccak256(
          abi.encode(
            _registerValidatorsTypeHash,
            keeperParams.validatorsRegistryRoot,
            keccak256(keeperParams.validators)
          )
        )
      );
  }

  /**
   * @notice Computes the hash of the EIP712 typed data
   * @dev This function is used to compute the hash of the EIP712 typed data
   * @return The hash of the EIP712 typed data
   */
  function _computeVaultValidatorsDomain() private view returns (bytes32) {
    return
      keccak256(
        abi.encode(
          keccak256(
            'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
          ),
          keccak256(bytes('VaultValidators')),
          keccak256('1'),
          block.chainid,
          address(this)
        )
      );
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[49] private __gap;
}
