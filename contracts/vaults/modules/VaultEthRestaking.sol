// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {ERC1967Proxy} from '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import {IVaultEthRestaking} from '../../interfaces/IVaultEthRestaking.sol';
import {IEigenPodOwner} from '../../interfaces/IEigenPodOwner.sol';
import {IEthValidatorsRegistry} from '../../interfaces/IEthValidatorsRegistry.sol';
import {Errors} from '../../libraries/Errors.sol';
import {VaultAdmin} from './VaultAdmin.sol';
import {VaultEthStaking} from './VaultEthStaking.sol';

/**
 * @title VaultEthRestaking
 * @author StakeWise
 * @notice Defines the logic for the Ethereum native restaking vault
 */
abstract contract VaultEthRestaking is VaultAdmin, VaultEthStaking, IVaultEthRestaking {
  using EnumerableSet for EnumerableSet.AddressSet;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address private immutable _eigenPodOwnerImplementation;

  /// @inheritdoc IVaultEthRestaking
  address public override restakeOperatorsManager;

  /// @inheritdoc IVaultEthRestaking
  address public override restakeWithdrawalsManager;

  EnumerableSet.AddressSet private _eigenPods;
  EnumerableSet.AddressSet internal _eigenPodOwners;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param eigenPodOwnerImplementation The address of the EigenPodOwner implementation contract
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(address eigenPodOwnerImplementation) {
    _eigenPodOwnerImplementation = eigenPodOwnerImplementation;
  }

  /// @inheritdoc IVaultEthRestaking
  function getEigenPods() external view override returns (address[] memory) {
    return _eigenPods.values();
  }

  /// @inheritdoc IVaultEthRestaking
  function createEigenPod() external override {
    if (msg.sender != restakeOperatorsManager) revert Errors.AccessDenied();

    // create a new EigenPodOwner
    address eigenPodOwner = address(new ERC1967Proxy(_eigenPodOwnerImplementation, ''));
    IEigenPodOwner(eigenPodOwner).initialize('');

    // add eigen pod to the list of vault's eigen pods
    address eigenPod = IEigenPodOwner(eigenPodOwner).eigenPod();
    _eigenPods.add(eigenPod);
    _eigenPodOwners.add(eigenPodOwner);

    // emit event
    emit EigenPodCreated(eigenPodOwner, eigenPod);
  }

  /// @inheritdoc IVaultEthRestaking
  function setRestakeOperatorsManager(address _restakeOperatorsManager) external override {
    if (restakeOperatorsManager == _restakeOperatorsManager) revert Errors.ValueNotChanged();
    _checkAdmin();
    restakeOperatorsManager = _restakeOperatorsManager;
    emit RestakeOperatorsManagerUpdated(_restakeOperatorsManager);
  }

  /// @inheritdoc IVaultEthRestaking
  function setRestakeWithdrawalsManager(address _restakeWithdrawalsManager) external override {
    if (restakeWithdrawalsManager == _restakeWithdrawalsManager) revert Errors.ValueNotChanged();
    _checkAdmin();
    restakeWithdrawalsManager = _restakeWithdrawalsManager;
    emit RestakeWithdrawalsManagerUpdated(_restakeWithdrawalsManager);
  }

  /// @inheritdoc VaultEthStaking
  function _registerSingleValidator(bytes calldata validator) internal virtual override {
    bytes calldata publicKey = validator[:48];
    IEthValidatorsRegistry(_validatorsRegistry).deposit{value: _validatorDeposit()}(
      publicKey,
      _extractWithdrawalCredentials(validator[176:validator.length]),
      validator[48:144],
      bytes32(validator[144:176])
    );
    emit ValidatorRegistered(publicKey);
  }

  /// @inheritdoc VaultEthStaking
  function _registerMultipleValidators(bytes calldata validators) internal virtual override {
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

  /// @inheritdoc VaultEthStaking
  function _validatorLength() internal pure virtual override returns (uint256) {
    return 196;
  }

  /**
   * @dev Internal function to extract the withdrawal credentials from the validator data
   * @param withdrawalAddress The withdrawal address in bytes
   * @return The credentials used for the validators withdrawals
   */
  function _extractWithdrawalCredentials(
    bytes calldata withdrawalAddress
  ) private view returns (bytes memory) {
    if (withdrawalAddress.length != 20) revert Errors.InvalidWithdrawalCredentials();

    // check if the EigenPod exists
    address eigenPod = abi.decode(withdrawalAddress, (address));
    if (!_eigenPods.contains(eigenPod)) {
      revert Errors.EigenPodNotFound();
    }
    return abi.encodePacked(bytes1(0x01), bytes11(0x0), eigenPod);
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
