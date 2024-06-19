// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {ReentrancyGuardUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
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
  ReentrancyGuardUpgradeable,
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
  function _registerSingleValidator(bytes calldata validator) internal virtual override {
    bytes calldata publicKey = validator[:48];
    IEthValidatorsRegistry(_validatorsRegistry).deposit{value: _validatorDeposit()}(
      publicKey,
      _withdrawalCredentials(),
      validator[48:144],
      bytes32(validator[144:_validatorLength()])
    );
    emit ValidatorRegistered(publicKey);
  }

  /// @inheritdoc VaultValidators
  function _registerMultipleValidators(bytes calldata validators) internal virtual override {
    uint256 startIndex;
    uint256 endIndex;
    uint256 validatorsCount = validators.length / _validatorLength();
    bytes memory withdrawalCredentials = _withdrawalCredentials();
    bytes calldata validator;
    bytes calldata publicKey;
    for (uint256 i = 0; i < validatorsCount; ) {
      unchecked {
        // cannot realistically overflow
        endIndex += _validatorLength();
      }
      validator = validators[startIndex:endIndex];
      publicKey = validator[:48];
      IEthValidatorsRegistry(_validatorsRegistry).deposit{value: _validatorDeposit()}(
        publicKey,
        withdrawalCredentials,
        validator[48:144],
        bytes32(validator[144:_validatorLength()])
      );
      emit ValidatorRegistered(publicKey);
      startIndex = endIndex;
      unchecked {
        // cannot realistically overflow
        ++i;
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
  function _validatorLength() internal pure virtual override returns (uint256) {
    return 176;
  }

  /// @inheritdoc VaultValidators
  function _validatorDeposit() internal pure virtual override returns (uint256) {
    return 32 ether;
  }

  /**
   * @dev Internal function for calculating Vault withdrawal credentials
   * @return The credentials used for the validators withdrawals
   */
  function _withdrawalCredentials() private view returns (bytes memory) {
    return abi.encodePacked(bytes1(0x01), bytes11(0x0), address(this));
  }

  /**
   * @dev Initializes the VaultEthStaking contract
   */
  function __VaultEthStaking_init() internal onlyInitializing {
    __ReentrancyGuard_init();

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
