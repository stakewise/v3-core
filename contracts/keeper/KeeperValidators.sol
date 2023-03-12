// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {IValidatorsRegistry} from '../interfaces/IValidatorsRegistry.sol';
import {IOracles} from '../interfaces/IOracles.sol';
import {IVaultsRegistry} from '../interfaces/IVaultsRegistry.sol';
import {IKeeperValidators} from '../interfaces/IKeeperValidators.sol';
import {KeeperRewards} from './KeeperRewards.sol';

/**
 * @title KeeperValidators
 * @author StakeWise
 * @notice Defines the functionality for approving validators' registrations
 */
abstract contract KeeperValidators is KeeperRewards, IKeeperValidators {
  bytes32 internal constant _registerValidatorsTypeHash =
    keccak256(
      'KeeperValidators(bytes32 validatorsRegistryRoot,address vault,bytes32 validators,bytes32 exitSignaturesIpfsHash)'
    );

  /// @inheritdoc IKeeperValidators
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IValidatorsRegistry public immutable override validatorsRegistry;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param _oracles The address of the Oracles contract
   * @param _vaultsRegistry The address of the VaultsRegistry contract
   * @param _validatorsRegistry The address of the beacon chain validators registry contract
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    IOracles _oracles,
    IVaultsRegistry _vaultsRegistry,
    IValidatorsRegistry _validatorsRegistry
  ) KeeperRewards(_oracles, _vaultsRegistry) {
    validatorsRegistry = _validatorsRegistry;
  }

  /// @inheritdoc IKeeperValidators
  function approveValidators(ApprovalParams calldata params) external override {
    if (validatorsRegistry.get_deposit_root() != params.validatorsRegistryRoot) {
      revert InvalidValidatorsRegistryRoot();
    }
    if (!vaultsRegistry.vaults(msg.sender)) revert AccessDenied();

    // verify all oracles approved registration
    oracles.verifyAllSignatures(
      keccak256(
        abi.encode(
          _registerValidatorsTypeHash,
          params.validatorsRegistryRoot,
          msg.sender,
          keccak256(params.validators),
          keccak256(bytes(params.exitSignaturesIpfsHash))
        )
      ),
      params.signatures
    );

    _collateralize(msg.sender);

    emit ValidatorsApproval(
      msg.sender,
      params.validators,
      params.exitSignaturesIpfsHash,
      block.timestamp
    );
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
