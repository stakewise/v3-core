// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {IEthValidatorsRegistry} from '../../interfaces/IEthValidatorsRegistry.sol';
import {IKeeperRewards} from '../../interfaces/IKeeperRewards.sol';
import {IVaultEthStaking} from '../../interfaces/IVaultEthStaking.sol';
import {Errors} from '../../libraries/Errors.sol';
import {VaultValidators} from './VaultValidators.sol';
import {VaultState} from './VaultState.sol';
import {VaultEnterExit} from './VaultEnterExit.sol';
import {VaultMev} from './VaultMev.sol';

/**
 * @title VaultEthStaking
 * @author StakeWise
 * @notice Defines the Ethereum staking functionality for the Vault
 */
abstract contract VaultEthStaking is
  Initializable,
  VaultState,
  VaultValidators,
  VaultEnterExit,
  VaultMev,
  IVaultEthStaking
{
  uint256 private constant _securityDeposit = 1e9;

  /// @inheritdoc IVaultEthStaking
  function deposit(
    address receiver,
    address referrer
  ) public payable virtual override returns (uint256 shares) {
    return _deposit(receiver, msg.value, referrer);
  }

  /// @inheritdoc IVaultEthStaking
  function updateStateAndDeposit(
    address receiver,
    address referrer,
    IKeeperRewards.HarvestParams calldata harvestParams
  ) public payable virtual override returns (uint256 shares) {
    updateState(harvestParams);
    return deposit(receiver, referrer);
  }

  /**
   * @dev Function for depositing using fallback function
   */
  receive() external payable virtual {
    _deposit(msg.sender, msg.value, address(0));
  }

  /// @inheritdoc IVaultEthStaking
  function receiveFromMevEscrow() external payable override {
    if (msg.sender != mevEscrow()) revert Errors.AccessDenied();
  }

  /// @inheritdoc VaultValidators
  function _registerValidator(
    bytes calldata validator,
    bool isTopUp,
    bool isV1Validator
  ) internal virtual override returns (uint256 depositAmount) {
    bytes calldata publicKey = validator[:48];
    bytes calldata signature = validator[48:144];
    bytes32 depositDataRoot = bytes32(validator[144:176]);

    // get the deposit amount and withdrawal credentials prefix
    bytes1 withdrawalCredsPrefix;
    if (isV1Validator) {
      withdrawalCredsPrefix = 0x01;
      depositAmount = _validatorMinEffectiveBalance();
    } else {
      withdrawalCredsPrefix = 0x02;
      // extract amount from data, convert gwei to wei by multiplying by 1 gwei
      depositAmount = (uint256(uint64(bytes8(validator[176:184]))) * 1 gwei);
      // should not exceed the max effective balance
      if (depositAmount > _validatorMaxEffectiveBalance()) revert Errors.InvalidAssets();
    }

    // deposit to the validators registry
    IEthValidatorsRegistry(_validatorsRegistry).deposit{value: depositAmount}(
      publicKey,
      abi.encodePacked(withdrawalCredsPrefix, bytes11(0x0), address(this)),
      signature,
      depositDataRoot
    );

    bytes32 publicKeyHash = keccak256(publicKey);
    if (isTopUp) {
      // check whether validator is tracked in case of the top-up
      if (!trackedValidators[publicKeyHash]) revert Errors.InvalidValidators();
      emit ValidatorFunded(publicKey, depositAmount);
    } else {
      // mark validator public key as tracked
      trackedValidators[publicKeyHash] = true;
      if (isV1Validator) {
        emit ValidatorRegistered(publicKey);
      } else {
        emit ValidatorRegistered(publicKey, depositAmount);
      }
    }
  }

  /// @inheritdoc VaultState
  function _vaultAssets() internal view virtual override returns (uint256) {
    return address(this).balance;
  }

  /// @inheritdoc VaultEnterExit
  function _transferVaultAssets(
    address receiver,
    uint256 assets
  ) internal virtual override nonReentrant {
    return Address.sendValue(payable(receiver), assets);
  }

  /// @inheritdoc VaultValidators
  function _validatorMinEffectiveBalance() internal pure virtual override returns (uint256) {
    return 32 ether;
  }

  /// @inheritdoc VaultValidators
  function _validatorMaxEffectiveBalance() internal pure virtual override returns (uint256) {
    return 2048 ether;
  }

  /**
   * @dev Initializes the VaultEthStaking contract
   */
  function __VaultEthStaking_init() internal onlyInitializing {
    // see https://github.com/OpenZeppelin/openzeppelin-contracts/issues/3706
    if (msg.value < _securityDeposit) revert Errors.InvalidSecurityDeposit();
    _deposit(address(this), msg.value, address(0));
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
