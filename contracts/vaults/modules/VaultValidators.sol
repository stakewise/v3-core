// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {MerkleProof} from '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
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
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address private immutable _depositDataRegistry;

  /// deprecated. Deposit data management is moved to DepositDataRegistry contract
  bytes32 private _validatorsRoot;

  /// deprecated. Deposit data management is moved to DepositDataRegistry contract
  uint256 private _validatorIndex;

  address private _validatorsManager;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param depositDataRegistry The address of the DepositDataRegistry contract
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(address depositDataRegistry) {
    _depositDataRegistry = depositDataRegistry;
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
    IKeeperValidators.ApprovalParams calldata keeperParams
  ) external override {
    // get approval from oracles
    IKeeperValidators(_keeper).approveValidators(keeperParams);

    // check vault is up to date
    _checkHarvested();

    // check access
    if (msg.sender != validatorsManager()) revert Errors.AccessDenied();

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
  function __VaultValidators_init() internal view onlyInitializing {
    if (capacity() < _validatorDeposit()) revert Errors.InvalidCapacity();
  }

  /**
   * @dev Initializes the V2 of the VaultValidators contract
   */
  function __VaultValidators_initV2() internal onlyInitializing {
    IDepositDataRegistry(_depositDataRegistry).migrate(
      _validatorsRoot,
      _validatorIndex,
      _validatorsManager
    );

    // clean up variables
    delete _validatorsRoot;
    delete _validatorIndex;
    delete _validatorsManager;
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
