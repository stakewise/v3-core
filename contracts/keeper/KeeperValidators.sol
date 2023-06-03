// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {IValidatorsRegistry} from '../interfaces/IValidatorsRegistry.sol';
import {IKeeperValidators} from '../interfaces/IKeeperValidators.sol';
import {KeeperRewards} from './KeeperRewards.sol';

/**
 * @title KeeperValidators
 * @author StakeWise
 * @notice Defines the functionality for approving validators' registrations and updating exit signatures
 */
abstract contract KeeperValidators is KeeperRewards, IKeeperValidators {
  bytes32 private constant _registerValidatorsTypeHash =
    keccak256(
      'KeeperValidators(bytes32 validatorsRegistryRoot,address vault,bytes32 validators,bytes32 exitSignaturesIpfsHash)'
    );

  bytes32 private constant _updateExitSigTypeHash =
    keccak256('KeeperValidators(address vault,bytes32 exitSignaturesIpfsHash,uint256 nonce)');

  IValidatorsRegistry private immutable _validatorsRegistry;

  /// @inheritdoc IKeeperValidators
  mapping(address => uint256) public override exitSignaturesNonces;

  /**
   * @dev Constructor
   * @param validatorsRegistry The address of the beacon chain validators registry contract
   */
  constructor(IValidatorsRegistry validatorsRegistry) {
    _validatorsRegistry = validatorsRegistry;
  }

  /// @inheritdoc IKeeperValidators
  function approveValidators(ApprovalParams calldata params) external override {
    // verify oracles approved registration for the current validators registry contract state
    if (_validatorsRegistry.get_deposit_root() != params.validatorsRegistryRoot) {
      revert InvalidValidatorsRegistryRoot();
    }
    if (!_vaultsRegistry.vaults(msg.sender)) revert AccessDenied();

    // verify all oracles approved registration
    _oracles.verifyAllSignatures(
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
    if (!(_vaultsRegistry.vaults(vault) && isCollateralized(vault))) revert InvalidVault();

    // SLOAD to memory
    uint256 nonce = exitSignaturesNonces[vault];

    // verify all oracles approved update
    _oracles.verifyAllSignatures(
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
}
