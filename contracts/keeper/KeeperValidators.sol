// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IValidatorsRegistry} from '../interfaces/IValidatorsRegistry.sol';
import {IKeeperValidators} from '../interfaces/IKeeperValidators.sol';
import {Errors} from '../libraries/Errors.sol';
import {KeeperOracles} from './KeeperOracles.sol';
import {KeeperRewards} from './KeeperRewards.sol';

/**
 * @title KeeperValidators
 * @author StakeWise
 * @notice Defines the functionality for approving validators' registrations and updating exit signatures
 */
abstract contract KeeperValidators is KeeperOracles, KeeperRewards, IKeeperValidators {
  bytes32 private constant _registerValidatorsTypeHash =
    keccak256(
      'KeeperValidators(bytes32 validatorsRegistryRoot,address vault,bytes validators,string exitSignaturesIpfsHash,uint256 deadline)'
    );

  bytes32 private constant _updateExitSigTypeHash =
    keccak256(
      'KeeperValidators(address vault,string exitSignaturesIpfsHash,uint256 nonce,uint256 deadline)'
    );

  IValidatorsRegistry private immutable _validatorsRegistry;

  /// @inheritdoc IKeeperValidators
  mapping(address => uint256) public override exitSignaturesNonces;

  /// @inheritdoc IKeeperValidators
  uint256 public override validatorsMinOracles;

  /**
   * @dev Constructor
   * @param validatorsRegistry The address of the beacon chain validators registry contract
   */
  constructor(IValidatorsRegistry validatorsRegistry) {
    _validatorsRegistry = validatorsRegistry;
  }

  /// @inheritdoc IKeeperValidators
  function setValidatorsMinOracles(uint256 _validatorsMinOracles) external override onlyOwner {
    _setValidatorsMinOracles(_validatorsMinOracles);
  }

  /// @inheritdoc IKeeperValidators
  function approveValidators(ApprovalParams calldata params) external override {
    if (params.deadline < block.timestamp) revert Errors.DeadlineExpired();

    // verify oracles approved registration for the current validators registry contract state
    if (_validatorsRegistry.get_deposit_root() != params.validatorsRegistryRoot) {
      revert Errors.InvalidValidatorsRegistryRoot();
    }
    if (!_vaultsRegistry.vaults(msg.sender)) revert Errors.AccessDenied();

    // verify oracles approved registration
    _verifySignatures(
      validatorsMinOracles,
      keccak256(
        abi.encode(
          _registerValidatorsTypeHash,
          params.validatorsRegistryRoot,
          msg.sender,
          keccak256(params.validators),
          keccak256(bytes(params.exitSignaturesIpfsHash)),
          params.deadline
        )
      ),
      params.signatures
    );

    _collateralize(msg.sender);

    emit ValidatorsApproval(msg.sender, params.exitSignaturesIpfsHash);
  }

  /// @inheritdoc IKeeperValidators
  function updateExitSignatures(
    address vault,
    uint256 deadline,
    string calldata exitSignaturesIpfsHash,
    bytes calldata oraclesSignatures
  ) external override {
    if (!(_vaultsRegistry.vaults(vault) && isCollateralized(vault))) revert Errors.InvalidVault();
    if (deadline < block.timestamp) revert Errors.DeadlineExpired();

    // SLOAD to memory
    uint256 nonce = exitSignaturesNonces[vault];

    // verify oracles approved signatures update
    _verifySignatures(
      validatorsMinOracles,
      keccak256(
        abi.encode(
          _updateExitSigTypeHash,
          vault,
          keccak256(bytes(exitSignaturesIpfsHash)),
          nonce,
          deadline
        )
      ),
      oraclesSignatures
    );

    // update state
    unchecked {
      // cannot realistically overflow
      exitSignaturesNonces[vault] = nonce + 1;
    }

    // emit event
    emit ExitSignaturesUpdated(msg.sender, vault, nonce, exitSignaturesIpfsHash);
  }

  /**
   * @dev Internal function to set the minimum number of oracles required to approve validators
   * @param _validatorsMinOracles The new minimum number of oracles required to approve validators
   */
  function _setValidatorsMinOracles(uint256 _validatorsMinOracles) private {
    if (_validatorsMinOracles == 0 || totalOracles < _validatorsMinOracles) {
      revert Errors.InvalidOracles();
    }
    validatorsMinOracles = _validatorsMinOracles;
    emit ValidatorsMinOraclesUpdated(_validatorsMinOracles);
  }
}
