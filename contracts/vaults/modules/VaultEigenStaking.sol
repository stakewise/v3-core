// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IVaultEigenStaking} from '../../interfaces/IVaultEigenStaking.sol';
import {IEthValidatorsRegistry} from '../../interfaces/IEthValidatorsRegistry.sol';
import {IEigenPods} from '../../interfaces/IEigenPods.sol';
import {Errors} from '../../libraries/Errors.sol';
import {VaultValidators} from './VaultValidators.sol';
import {VaultEthStaking} from './VaultEthStaking.sol';

/**
 * @title VaultEigenStaking
 * @author StakeWise
 * @notice Defines the EigenLayer staking functionality for the Vault
 */
abstract contract VaultEigenStaking is
  Initializable,
  VaultValidators,
  VaultEthStaking,
  IVaultEigenStaking
{
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IEigenPods private immutable _eigenPods;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param eigenPods The address of the EigenPods contract
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(address eigenPods) {
    _eigenPods = IEigenPods(eigenPods);
  }

  /// @inheritdoc IVaultEigenStaking
  function isEigenVault() external pure override returns (bool) {
    return true;
  }

  /// @inheritdoc IVaultEigenStaking
  function receiveEigenAssets() external payable override {
    if (_eigenPods.getProxyPod(msg.sender) == address(0)) revert Errors.AccessDenied();
  }

  /// @inheritdoc VaultValidators
  function _registerSingleValidator(
    bytes calldata validator
  ) internal virtual override(VaultValidators, VaultEthStaking) {
    bytes calldata publicKey = validator[:48];
    IEthValidatorsRegistry(_validatorsRegistry).deposit{value: _validatorDeposit()}(
      publicKey,
      _extractWithdrawalCredentials(validator[176:validator.length]),
      validator[48:144],
      bytes32(validator[144:176])
    );
    emit ValidatorRegistered(publicKey);
  }

  /// @inheritdoc VaultValidators
  function _registerMultipleValidators(
    bytes calldata validators
  ) internal virtual override(VaultValidators, VaultEthStaking) {
    uint256 startIndex;
    uint256 endIndex;
    uint256 validatorLength = _validatorLength();
    uint256 validatorsCount = validators.length / validatorLength;
    bytes calldata validator;
    bytes calldata publicKey;
    for (uint256 i = 0; i < validatorsCount; ) {
      unchecked {
        // cannot realistically overflow
        endIndex += validatorLength;
      }
      validator = validators[startIndex:endIndex];
      publicKey = validator[:48];
      IEthValidatorsRegistry(_validatorsRegistry).deposit{value: _validatorDeposit()}(
        publicKey,
        _extractWithdrawalCredentials(validator[176:validator.length]),
        validator[48:144],
        bytes32(validator[144:validatorLength])
      );
      emit ValidatorRegistered(publicKey);
      startIndex = endIndex;
      unchecked {
        // cannot realistically overflow
        ++i;
      }
    }
  }

  /**
   * @dev Internal function to extract the withdrawal credentials from the validator data
   * @param eigenPodBytes The bytes containing the address of the EigenPod
   * @return The credentials used for the validators withdrawals
   */
  function _extractWithdrawalCredentials(
    bytes calldata eigenPodBytes
  ) private view returns (bytes memory) {
    if (eigenPodBytes.length != 20) revert Errors.EigenInvalidWithdrawalCredentials();

    // check if the EigenPod exists
    address eigenPod = abi.decode(eigenPodBytes, (address));
    if (!_eigenPods.isVaultPod(address(this), eigenPod)) revert Errors.EigenPodNotFound();

    return abi.encodePacked(bytes1(0x01), bytes11(0x0), eigenPod);
  }

  /// @inheritdoc VaultEthStaking
  function _withdrawalCredentials() internal view virtual override returns (bytes memory) {}

  /// @inheritdoc VaultValidators
  function _validatorLength()
    internal
    pure
    virtual
    override(VaultValidators, VaultEthStaking)
    returns (uint256)
  {
    return 196;
  }

  /**
   * @dev Initializes the VaultEigenStaking contract
   */
  function __VaultEigenStaking_init() internal onlyInitializing {
    _eigenPods.createEigenPod(address(this));
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
