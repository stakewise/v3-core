// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IValidatorsRegistry} from '../interfaces/IValidatorsRegistry.sol';
import {IOracles} from '../interfaces/IOracles.sol';
import {IVaultsRegistry} from '../interfaces/IVaultsRegistry.sol';
import {IKeeperValidators} from '../interfaces/IKeeperValidators.sol';
import {KeeperRewards} from './KeeperRewards.sol';

/**
 * @title KeeperValidators
 * @author StakeWise
 * @notice Defines the functionality for approving validators' registrations and updating exit signatures
 */
abstract contract KeeperValidators is Initializable, KeeperRewards, IKeeperValidators {
  bytes32 internal constant _registerValidatorsTypeHash =
    keccak256(
      'KeeperValidators(bytes32 validatorsRegistryRoot,address vault,bytes32 validators,bytes32 exitSignaturesIpfsHash)'
    );

  bytes32 internal constant _updateExitSigTypeHash =
    keccak256('KeeperValidators(address vault,bytes32 exitSignaturesIpfsHash,uint256 nonce)');

  /// @inheritdoc IKeeperValidators
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IValidatorsRegistry public immutable override validatorsRegistry;

  /// @inheritdoc IKeeperValidators
  mapping(address => uint256) public override exitSignaturesNonces;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param _oracles The address of the Oracles contract
   * @param _vaultsRegistry The address of the VaultsRegistry contract
   * @param _validatorsRegistry The address of the beacon chain validators registry contract
   * @param sharedMevEscrow The address of the shared MEV escrow contract
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    IOracles _oracles,
    IVaultsRegistry _vaultsRegistry,
    IValidatorsRegistry _validatorsRegistry,
    address sharedMevEscrow
  ) KeeperRewards(_oracles, _vaultsRegistry, sharedMevEscrow) {
    validatorsRegistry = _validatorsRegistry;
  }

  /// @inheritdoc IKeeperValidators
  function approveValidators(ApprovalParams calldata params) external override {
    // verify oracles approved registration for the current validators registry contract state
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

  /// @inheritdoc IKeeperValidators
  function updateExitSignatures(
    address vault,
    string calldata exitSignaturesIpfsHash,
    bytes calldata oraclesSignatures
  ) external override {
    if (!(vaultsRegistry.vaults(vault) && isCollateralized(vault))) revert InvalidVault();

    // SLOAD to memory
    uint256 nonce = exitSignaturesNonces[vault];

    // verify all oracles approved update
    oracles.verifyAllSignatures(
      keccak256(
        abi.encode(_updateExitSigTypeHash, vault, keccak256(bytes(exitSignaturesIpfsHash)), nonce)
      ),
      oraclesSignatures
    );

    // update state
    exitSignaturesNonces[vault] = nonce + 1;

    // emit event
    emit ExitSignaturesUpdated(msg.sender, vault, nonce, exitSignaturesIpfsHash);
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
