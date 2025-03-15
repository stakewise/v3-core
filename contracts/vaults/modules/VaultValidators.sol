// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {ReentrancyGuardUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
import {SignatureChecker} from '@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol';
import {IKeeperValidators} from '../../interfaces/IKeeperValidators.sol';
import {IVaultValidators} from '../../interfaces/IVaultValidators.sol';
import {IConsolidationsChecker} from '../../interfaces/IConsolidationsChecker.sol';
import {IDepositDataRegistry} from '../../interfaces/IDepositDataRegistry.sol';
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
  ReentrancyGuardUpgradeable,
  VaultAdmin,
  VaultState,
  IVaultValidators
{
  bytes32 private constant _validatorsManagerTypeHash =
    keccak256('VaultValidators(bytes32 validatorsRegistryRoot,bytes validators)');
  uint256 internal constant _validatorV1DepositLength = 176;
  uint256 internal constant _validatorV2DepositLength = 184;
  uint256 private constant _validatorWithdrawalLength = 56;
  uint256 private constant _validatorConsolidationLength = 96;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address private immutable _depositDataRegistry;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  uint256 private immutable _initialChainId;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address internal immutable _validatorsRegistry;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address private immutable _validatorsWithdrawals;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address private immutable _validatorsConsolidations;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address private immutable _consolidationsChecker;

  /// deprecated. Deposit data management is moved to DepositDataRegistry contract
  bytes32 private __deprecated__validatorsRoot;

  /// deprecated. Deposit data management is moved to DepositDataRegistry contract
  uint256 private __deprecated__validatorIndex;

  address private _validatorsManager;

  bytes32 private _initialDomainSeparator;

  /// @inheritdoc IVaultValidators
  mapping(bytes32 publicKeyHash => bool isRegistered) public override trackedValidators;

  /// @inheritdoc IVaultValidators
  uint256 public override validatorsManagerNonce;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param depositDataRegistry The address of the deposit data registry contract
   * @param validatorsRegistry The contract address used for registering validators in beacon chain
   * @param validatorsWithdrawals The contract address used for withdrawing validators in beacon chain
   * @param validatorsConsolidations The contract address used for consolidating validators in beacon chain
   * @param consolidationsChecker The contract address used for verifying consolidation approvals
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address depositDataRegistry,
    address validatorsRegistry,
    address validatorsWithdrawals,
    address validatorsConsolidations,
    address consolidationsChecker
  ) {
    _initialChainId = block.chainid;
    _depositDataRegistry = depositDataRegistry;
    _validatorsRegistry = validatorsRegistry;
    _validatorsWithdrawals = validatorsWithdrawals;
    _validatorsConsolidations = validatorsConsolidations;
    _consolidationsChecker = consolidationsChecker;
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
    // check whether oracles have approve validators registration
    IKeeperValidators(_keeper).approveValidators(keeperParams);
    _registerValidators(
      keeperParams.validators,
      keeperParams.validatorsRegistryRoot,
      validatorsManagerSignature,
      false
    );
  }

  /// @inheritdoc IVaultValidators
  function fundValidators(
    bytes calldata validators,
    bytes calldata validatorsManagerSignature
  ) external override {
    _registerValidators(
      validators,
      bytes32(validatorsManagerNonce),
      validatorsManagerSignature,
      true
    );
  }

  /// @inheritdoc IVaultValidators
  function withdrawValidators(
    bytes calldata validators,
    bytes calldata validatorsManagerSignature
  ) external payable override nonReentrant {
    _checkCanWithdrawValidators(validators, validatorsManagerSignature);

    // check validators length is valid
    uint256 validatorsCount = validators.length / _validatorWithdrawalLength;
    unchecked {
      if (
        validatorsCount == 0 || validatorsCount * _validatorWithdrawalLength != validators.length
      ) {
        revert Errors.InvalidValidators();
      }
    }

    uint256 feePaid;
    uint256 withdrawnAmount;
    uint256 totalFeeAssets = msg.value;
    bytes calldata publicKey;
    uint256 startIndex;
    uint256 endIndex;
    for (uint256 i = 0; i < validatorsCount; ) {
      unchecked {
        // cannot realistically overflow
        endIndex += _validatorWithdrawalLength;
      }

      (publicKey, withdrawnAmount, feePaid) = _withdrawValidator(validators[startIndex:endIndex]);
      totalFeeAssets -= feePaid;
      emit ValidatorWithdrawn(publicKey, withdrawnAmount, feePaid);

      startIndex = endIndex;
      unchecked {
        // cannot realistically overflow
        ++i;
      }
    }

    if (totalFeeAssets > 0) {
      Address.sendValue(payable(msg.sender), totalFeeAssets);
    }
  }

  /// @inheritdoc IVaultValidators
  function consolidateValidators(
    bytes calldata validators,
    bytes calldata validatorsManagerSignature,
    bytes calldata oracleSignatures
  ) external payable override {
    if (
      !_isValidatorsManager(validators, bytes32(validatorsManagerNonce), validatorsManagerSignature)
    ) {
      revert Errors.AccessDenied();
    }

    // Check validators length is valid
    uint256 validatorsCount = validators.length / _validatorConsolidationLength;
    unchecked {
      if (
        validatorsCount == 0 || validatorsCount * _validatorConsolidationLength != validators.length
      ) {
        revert Errors.InvalidValidators();
      }
    }

    // Process the consolidation in smaller batches to avoid stack depth issues
    _processConsolidation(validators, validatorsCount, oracleSignatures);
  }

  /**
   * @dev Internal function to process validator consolidations
   * @param validators The concatenated validators data
   * @param validatorsCount The number of validators to consolidate
   * @param oracleSignatures The optional signatures from the oracles
   */
  function _processConsolidation(
    bytes calldata validators,
    uint256 validatorsCount,
    bytes calldata oracleSignatures
  ) private {
    // Check for oracle approval if signatures provided
    bool consolidationsApproved = false;
    if (oracleSignatures.length > 0) {
      // Check whether oracles have approved validators consolidation
      IConsolidationsChecker(_consolidationsChecker).verifySignatures(
        address(this),
        validators,
        oracleSignatures
      );
      consolidationsApproved = true;
    }

    uint256 totalFeeAssets = msg.value;

    // Process each validator
    for (uint256 i = 0; i < validatorsCount; ) {
      uint256 startIndex = i * _validatorConsolidationLength;
      uint256 endIndex = startIndex + _validatorConsolidationLength;

      (
        bytes calldata sourcePublicKey,
        bytes calldata destPublicKey,
        uint256 feePaid
      ) = _consolidateValidator(validators[startIndex:endIndex]);

      // Handle destination public key validation
      bytes32 publicKeyHash = keccak256(destPublicKey);
      if (!trackedValidators[publicKeyHash]) {
        // Consolidations are only allowed for tracked or approved validators
        if (!consolidationsApproved) revert Errors.InvalidValidators();
        trackedValidators[publicKeyHash] = true;
      }

      // Update fees and emit event
      unchecked {
        totalFeeAssets -= feePaid;
        ++i;
      }

      emit ValidatorConsolidated(sourcePublicKey, destPublicKey, feePaid);
    }

    // refund unused fees
    if (totalFeeAssets > 0) {
      Address.sendValue(payable(msg.sender), totalFeeAssets);
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
   * @dev Internal function for registering validator
   * @param validator The validator registration data
   * @param isV1Validator Whether the validator is V1 or V2
   * @return publicKey The public key of the registered validator
   * @return depositAmount The amount of assets that was deposited
   */
  function _registerValidator(
    bytes calldata validator,
    bool isV1Validator
  ) internal virtual returns (bytes calldata publicKey, uint256 depositAmount);

  /**
   * @dev Internal function for withdrawing validator
   * @param validator The validator withdrawal data
   * @return publicKey The public key of the withdrawn validator
   * @return withdrawnAmount The amount of assets that was withdrawn
   * @return feePaid The amount of fee that was paid
   */
  function _withdrawValidator(
    bytes calldata validator
  ) internal virtual returns (bytes calldata publicKey, uint256 withdrawnAmount, uint256 feePaid) {
    publicKey = validator[:48];
    // convert gwei to wei by multiplying by 1 gwei
    withdrawnAmount = (uint256(uint64(bytes8(validator[48:56]))) * 1 gwei);
    feePaid = abi.decode(Address.functionCall(_validatorsWithdrawals, ''), (uint256));

    Address.functionCallWithValue(_validatorsWithdrawals, validator, feePaid);
  }

  /**
   * @dev Internal function for consolidating validators
   * @param fromPublicKey The public key of the validator that was consolidated
   * @param toPublicKey The public key of the validator that was consolidated to
   * @param feePaid The amount of fee that was paid
   */
  function _consolidateValidator(
    bytes calldata validator
  ) private returns (bytes calldata fromPublicKey, bytes calldata toPublicKey, uint256 feePaid) {
    fromPublicKey = validator[:48];
    toPublicKey = validator[48:96];
    feePaid = abi.decode(Address.functionCall(_validatorsConsolidations, ''), (uint256));

    Address.functionCallWithValue(_validatorsConsolidations, validator, feePaid);
  }

  /**
   * @dev Internal function for fetching validator minimum effective balance
   * @return The minimum effective balance for the validator
   */
  function _validatorMinEffectiveBalance() internal pure virtual returns (uint256);

  /**
   * @dev Internal function for fetching validator maximum effective balance
   * @return The maximum effective balance for the validator
   */
  function _validatorMaxEffectiveBalance() internal pure virtual returns (uint256);

  /**
   * @dev Internal function for registering validators
   * @param validators The concatenated validators data
   * @param nonce The nonce of the signature
   * @param validatorsManagerSignature The optional signature from the validators manager
   * @param isTopUp Whether the registration is a balance top-up
   */
  function _registerValidators(
    bytes calldata validators,
    bytes32 nonce,
    bytes calldata validatorsManagerSignature,
    bool isTopUp
  ) private {
    // check vault is up to date
    _checkHarvested();

    // check access
    if (!_isValidatorsManager(validators, nonce, validatorsManagerSignature)) {
      revert Errors.AccessDenied();
    }

    // check validators length is valid
    uint256 validatorsLength = validators.length;
    bool isV1Validators = validatorsLength % _validatorV1DepositLength == 0;
    bool isV2Validators = validatorsLength % _validatorV2DepositLength == 0;
    if (
      validatorsLength == 0 ||
      (isV1Validators && isV2Validators) ||
      (!isV1Validators && !isV2Validators)
    ) {
      revert Errors.InvalidValidators();
    }

    // top up is only allowed for V2 validators
    if (isTopUp && isV1Validators) {
      revert Errors.CannotTopUpV1Validators();
    }

    uint256 _validatorDepositLength = (
      isV1Validators ? _validatorV1DepositLength : _validatorV2DepositLength
    );
    uint256 validatorsCount = validatorsLength / _validatorDepositLength;

    bytes calldata publicKey;
    uint256 depositAmount;
    uint256 startIndex;
    uint256 endIndex;
    bytes32 publicKeyHash;

    uint256 availableDeposits = withdrawableAssets();
    for (uint256 i = 0; i < validatorsCount; ) {
      unchecked {
        // cannot realistically overflow
        endIndex += _validatorDepositLength;
      }

      (publicKey, depositAmount) = _registerValidator(
        validators[startIndex:endIndex],
        isV1Validators
      );
      availableDeposits -= depositAmount;

      publicKeyHash = keccak256(publicKey);
      if (isTopUp) {
        // check whether validator is tracked in case of the top-up
        if (!trackedValidators[publicKeyHash]) revert Errors.InvalidValidators();
        emit ValidatorFunded(publicKey, depositAmount);
      } else {
        // mark validator public key as tracked
        trackedValidators[publicKeyHash] = true;
        if (isV1Validators) {
          emit ValidatorRegistered(publicKey);
        } else {
          emit ValidatorRegistered(publicKey, depositAmount);
        }
      }

      startIndex = endIndex;
      unchecked {
        // cannot realistically overflow
        ++i;
      }
    }
  }

  /**
   * @dev Internal function for checking whether the caller can withdraw validators
   * @param validators The concatenated validators data
   * @param validatorsManagerSignature The optional signature from the validators manager
   */
  function _checkCanWithdrawValidators(
    bytes calldata validators,
    bytes calldata validatorsManagerSignature
  ) internal virtual;

  /**
   * @dev Internal function for checking whether the caller is the validators manager.
   *      If the valid signature is provided, update the nonce.
   * @param validators The concatenated validators data
   * @param nonce The nonce of the signature
   * @param validatorsManagerSignature The optional signature from the validators manager
   * @return true if the caller is the validators manager
   */
  function _isValidatorsManager(
    bytes calldata validators,
    bytes32 nonce,
    bytes calldata validatorsManagerSignature
  ) internal returns (bool) {
    // SLOAD to memory
    address validatorsManager_ = validatorsManager();
    if (msg.sender == validatorsManager_) {
      return true;
    }

    if (
      validatorsManager_ == address(0) ||
      validators.length == 0 ||
      validatorsManagerSignature.length == 0
    ) {
      return false;
    }

    // check signature
    bool isValidSignature = SignatureChecker.isValidSignatureNow(
      validatorsManager_,
      _getValidatorsManagerSigningMessage(nonce, validators),
      validatorsManagerSignature
    );

    // update signature nonce
    if (isValidSignature) {
      unchecked {
        // cannot realistically overflow
        validatorsManagerNonce += 1;
      }
    }

    return isValidSignature;
  }

  /**
   * @notice Get the message to be signed by the validators manager
   * @param nonce The nonce of the message
   * @param validators The concatenated validators data
   * @return The message to be signed
   */
  function _getValidatorsManagerSigningMessage(
    bytes32 nonce,
    bytes calldata validators
  ) private view returns (bytes32) {
    bytes32 domainSeparator = block.chainid == _initialChainId
      ? _initialDomainSeparator
      : _computeVaultValidatorsDomain();

    return
      MessageHashUtils.toTypedDataHash(
        domainSeparator,
        keccak256(abi.encode(_validatorsManagerTypeHash, nonce, keccak256(validators)))
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
   * @dev Upgrades the VaultValidators contract
   */
  function __VaultValidators_upgrade() internal onlyInitializing {
    __ReentrancyGuard_init();
    // initialize domain separator
    bytes32 newInitialDomainSeparator = _computeVaultValidatorsDomain();
    if (newInitialDomainSeparator != _initialDomainSeparator) {
      _initialDomainSeparator = newInitialDomainSeparator;
    }

    // migrate deposit data variables to DepositDataRegistry contract
    if (__deprecated__validatorsRoot != bytes32(0)) {
      IDepositDataRegistry(_depositDataRegistry).migrate(
        __deprecated__validatorsRoot,
        __deprecated__validatorIndex,
        _validatorsManager
      );
      delete __deprecated__validatorIndex;
      delete __deprecated__validatorsRoot;
      delete _validatorsManager;
    }
  }

  /**
   * @dev Initializes the VaultValidators contract
   * @dev NB! This initializer must be called after VaultState initializer
   */
  function __VaultValidators_init() internal onlyInitializing {
    __ReentrancyGuard_init();
    if (capacity() < _validatorMinEffectiveBalance()) revert Errors.InvalidCapacity();
    _initialDomainSeparator = _computeVaultValidatorsDomain();
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[47] private __gap;
}
