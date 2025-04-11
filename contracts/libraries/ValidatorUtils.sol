// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {MessageHashUtils} from '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
import {SignatureChecker} from '@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol';
import {Errors} from './Errors.sol';
import {IVaultValidators} from '../interfaces/IVaultValidators.sol';

/**
 * @title ValidatorUtils
 * @author StakeWise
 * @notice Includes functionality for managing the validators
 */
library ValidatorUtils {
  bytes32 private constant _validatorsManagerTypeHash =
    keccak256('VaultValidators(bytes32 nonce,bytes validators)');
  uint256 private constant _validatorV1DepositLength = 176;
  uint256 private constant _validatorV2DepositLength = 184;
  uint256 private constant _validatorWithdrawalLength = 56;
  uint256 private constant _validatorConsolidationLength = 96;
  uint256 private constant _validatorMinEffectiveBalance = 32 ether;
  uint256 private constant _validatorMaxEffectiveBalance = 2048 ether;

  /*
   * @dev Struct to hold the validator registration data
   * @param publicKey The public key of the validator
   * @param signature The signature of the validator
   * @param withdrawalCredentials The withdrawal credentials of the validator
   * @param depositDataRoot The deposit data root of the validator
   * @param depositAmount The deposit amount of the validator
   */
  struct ValidatorDeposit {
    bytes publicKey;
    bytes signature;
    bytes withdrawalCredentials;
    bytes32 depositDataRoot;
    uint256 depositAmount;
  }

  /**
   * @dev Function to check if the validator signature is valid
   * @param nonce The nonce of the validator
   * @param domainSeparator The domain separator of the validator
   * @param validatorsManager The address of the validators manager
   * @param validators The validators data
   * @param signature The signature of the validator
   * @return Whether the signature is valid
   */
  function isValidManagerSignature(
    bytes32 nonce,
    bytes32 domainSeparator,
    address validatorsManager,
    bytes calldata validators,
    bytes calldata signature
  ) external view returns (bool) {
    bytes32 messageHash = MessageHashUtils.toTypedDataHash(
      domainSeparator,
      keccak256(abi.encode(_validatorsManagerTypeHash, nonce, keccak256(validators)))
    );
    return SignatureChecker.isValidSignatureNow(validatorsManager, messageHash, signature);
  }

  /**
   * @dev Function to get the validator registration data
   * @param validator The validator data
   * @param isV1Validator Whether the validator is a V1 validator
   * @return validatorDeposit The validator registration data
   */
  function getValidatorDeposit(
    bytes calldata validator,
    bool isV1Validator
  ) internal view returns (ValidatorDeposit memory validatorDeposit) {
    validatorDeposit.publicKey = validator[:48];
    validatorDeposit.signature = validator[48:144];
    validatorDeposit.depositDataRoot = bytes32(validator[144:176]);

    // get the deposit amount and withdrawal credentials prefix
    bytes1 withdrawalCredsPrefix;
    if (isV1Validator) {
      withdrawalCredsPrefix = 0x01;
      validatorDeposit.depositAmount = _validatorMinEffectiveBalance;
    } else {
      withdrawalCredsPrefix = 0x02;
      // extract amount from data, convert gwei to wei by multiplying by 1 gwei
      validatorDeposit.depositAmount = (uint256(uint64(bytes8(validator[176:184]))) * 1 gwei);
    }
    validatorDeposit.withdrawalCredentials = abi.encodePacked(
      withdrawalCredsPrefix,
      bytes11(0x0),
      address(this)
    );
  }

  /**
   * @dev Function to get the type of validators
   * @param validatorsLength The length of the validators data
   * @return isV1Validators Whether the validators are V1 validators
   */
  function getIsV1Validators(uint256 validatorsLength) internal pure returns (bool) {
    bool isV1Validators = validatorsLength % _validatorV1DepositLength == 0;
    bool isV2Validators = validatorsLength % _validatorV2DepositLength == 0;
    if (
      validatorsLength == 0 ||
      (isV1Validators && isV2Validators) ||
      (!isV1Validators && !isV2Validators)
    ) {
      revert Errors.InvalidValidators();
    }

    return isV1Validators;
  }

  /**
   * @dev Function to get the validator registrations
   * @param v2Validators The mapping of public key hashes to registration status
   * @param validators The validators data
   * @param isTopUp Whether the registration is a top-up
   * @return validatorDeposits The array of validator registrations
   */
  function getValidatorDeposits(
    mapping(bytes32 publicKeyHash => bool isRegistered) storage v2Validators,
    bytes calldata validators,
    bool isTopUp
  ) external returns (ValidatorDeposit[] memory validatorDeposits) {
    // check validators length is valid
    uint256 validatorsLength = validators.length;
    bool isV1Validators = getIsV1Validators(validatorsLength);

    // top up is only allowed for V2 validators
    if (isTopUp && isV1Validators) {
      revert Errors.CannotTopUpV1Validators();
    }

    uint256 _validatorDepositLength = (
      isV1Validators ? _validatorV1DepositLength : _validatorV2DepositLength
    );
    uint256 validatorsCount = validatorsLength / _validatorDepositLength;

    uint256 startIndex;
    ValidatorDeposit memory valDeposit;
    validatorDeposits = new ValidatorDeposit[](validatorsCount);
    for (uint256 i = 0; i < validatorsCount; ) {
      valDeposit = getValidatorDeposit(
        validators[startIndex:startIndex + _validatorDepositLength],
        isV1Validators
      );

      if (isTopUp) {
        // check whether validator is tracked in case of the top-up
        if (!v2Validators[keccak256(valDeposit.publicKey)]) {
          revert Errors.InvalidValidators();
        }
        // add registration data to the array
        validatorDeposits[i] = valDeposit;
        emit IVaultValidators.ValidatorFunded(valDeposit.publicKey, valDeposit.depositAmount);
        unchecked {
          // cannot realistically overflow
          ++i;
          startIndex += _validatorDepositLength;
        }
        continue;
      }

      // check the registration amount
      if (
        valDeposit.depositAmount > _validatorMaxEffectiveBalance ||
        valDeposit.depositAmount < _validatorMinEffectiveBalance
      ) {
        revert Errors.InvalidAssets();
      }

      // mark v2 validator public key as tracked
      if (!isV1Validators) {
        v2Validators[keccak256(valDeposit.publicKey)] = true;
        emit IVaultValidators.V2ValidatorRegistered(valDeposit.publicKey, valDeposit.depositAmount);
      } else {
        emit IVaultValidators.ValidatorRegistered(valDeposit.publicKey);
      }

      // add registration data to the array
      validatorDeposits[i] = valDeposit;

      unchecked {
        // cannot realistically overflow
        ++i;
        startIndex += _validatorDepositLength;
      }
    }
  }

  /**
   * @dev Function to withdraw the validators
   * @param validators The validators data
   * @param validatorsWithdrawals The address of the validators withdrawals contract
   */
  function withdrawValidators(bytes calldata validators, address validatorsWithdrawals) external {
    // check validators length is valid
    uint256 validatorsCount = validators.length / _validatorWithdrawalLength;
    unchecked {
      if (validatorsCount == 0 || validators.length % _validatorWithdrawalLength != 0) {
        revert Errors.InvalidValidators();
      }
    }

    uint256 feePaid;
    uint256 withdrawnAmount;
    uint256 totalFeeAssets = msg.value;
    bytes calldata publicKey;
    bytes calldata validator;
    uint256 startIndex;
    for (uint256 i = 0; i < validatorsCount; ) {
      validator = validators[startIndex:startIndex + _validatorWithdrawalLength];
      publicKey = validator[:48];

      // convert gwei to wei by multiplying by 1 gwei
      withdrawnAmount = (uint256(uint64(bytes8(validator[48:56]))) * 1 gwei);
      feePaid = uint256(bytes32(Address.functionStaticCall(validatorsWithdrawals, '')));

      // submit validator withdrawal
      Address.functionCallWithValue(validatorsWithdrawals, validator, feePaid);
      totalFeeAssets -= feePaid;
      emit IVaultValidators.ValidatorWithdrawalSubmitted(publicKey, withdrawnAmount, feePaid);

      unchecked {
        // cannot realistically overflow
        ++i;
        startIndex += _validatorWithdrawalLength;
      }
    }

    // send the remaining assets to the caller
    if (totalFeeAssets > 0) {
      Address.sendValue(payable(msg.sender), totalFeeAssets);
    }
  }

  /**
   * @dev Internal function for consolidating validators
   * @param validator The validator data
   * @param validatorsConsolidations The address of the validators consolidations contract
   * @param fromPublicKey The public key of the validator that was consolidated
   * @param toPublicKey The public key of the validator that was consolidated to
   * @param feePaid The amount of fee that was paid
   */
  function consolidateValidator(
    bytes calldata validator,
    address validatorsConsolidations
  ) internal returns (bytes calldata fromPublicKey, bytes calldata toPublicKey, uint256 feePaid) {
    fromPublicKey = validator[:48];
    toPublicKey = validator[48:96];
    feePaid = uint256(bytes32(Address.functionStaticCall(validatorsConsolidations, '')));

    Address.functionCallWithValue(validatorsConsolidations, validator, feePaid);
  }

  /**
   * @dev Function to consolidate the validators
   * @param v2Validators The mapping of public key hashes to registration status
   * @param validators The validators data
   * @param consolidationsApproved Whether the consolidations are approved
   * @param validatorsConsolidations The address of the validators consolidations contract
   */
  function consolidateValidators(
    mapping(bytes32 publicKeyHash => bool isRegistered) storage v2Validators,
    bytes calldata validators,
    bool consolidationsApproved,
    address validatorsConsolidations
  ) external {
    // Check validators length is valid
    uint256 validatorsCount = validators.length / _validatorConsolidationLength;
    unchecked {
      if (validatorsCount == 0 || validators.length % _validatorConsolidationLength != 0) {
        revert Errors.InvalidValidators();
      }
    }

    uint256 totalFeeAssets = msg.value;

    // Process each validator
    bytes32 destPubKeyHash;
    bytes calldata sourcePublicKey;
    bytes calldata destPublicKey;
    uint256 feePaid;
    uint256 startIndex;
    for (uint256 i = 0; i < validatorsCount; ) {
      // consolidate validators
      (sourcePublicKey, destPublicKey, feePaid) = consolidateValidator(
        validators[startIndex:startIndex + _validatorConsolidationLength],
        validatorsConsolidations
      );

      // check whether the destination public key is tracked or approved
      destPubKeyHash = keccak256(destPublicKey);
      if (consolidationsApproved) {
        v2Validators[destPubKeyHash] = true;
      } else if (!v2Validators[destPubKeyHash]) {
        revert Errors.InvalidValidators();
      }

      // Update fees and emit event
      unchecked {
        // cannot realistically overflow
        totalFeeAssets -= feePaid;
        startIndex += _validatorConsolidationLength;
        ++i;
      }

      // emit event
      emit IVaultValidators.ValidatorConsolidationSubmitted(
        sourcePublicKey,
        destPublicKey,
        feePaid
      );
    }

    // refund unused fees
    if (totalFeeAssets > 0) {
      Address.sendValue(payable(msg.sender), totalFeeAssets);
    }
  }
}
