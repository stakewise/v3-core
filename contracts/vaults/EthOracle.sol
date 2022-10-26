// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {Oracle} from '../abstract/Oracle.sol';
import {IEthOracle} from '../interfaces/IEthOracle.sol';
import {IValidatorsRegistry} from '../interfaces/IValidatorsRegistry.sol';
import {IRegistry} from '../interfaces/IRegistry.sol';
import {ISigners} from '../interfaces/ISigners.sol';
import {IEthVault} from '../interfaces/IEthVault.sol';

/**
 * @title EthOracle
 * @author StakeWise
 * @notice Defines the functionality for registering validators for the Ethereum Vaults
 */
contract EthOracle is Oracle, IEthOracle {
  bytes32 internal constant _registerValidatorTypeHash =
    keccak256('EthOracle(bytes32 validatorsRegistryRoot,address vault,bytes32 validator)');
  bytes32 internal constant _registerValidatorsTypeHash =
    keccak256('EthOracle(bytes32 validatorsRegistryRoot,address vault,bytes32 validators)');

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param _signers The address of the Signers contract
   * @param _registry The address of the Registry contract
   * @param _validatorsRegistry The address of the Validators Registry contract
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    ISigners _signers,
    IRegistry _registry,
    IValidatorsRegistry _validatorsRegistry
  ) Oracle(_signers, _registry, _validatorsRegistry) {}

  /// @inheritdoc IEthOracle
  function initialize(address _owner) external override initializer {
    __Oracle_init(_owner);
  }

  /// @inheritdoc IEthOracle
  function registerValidator(
    address vault,
    bytes32 validatorsRegistryRoot,
    bytes calldata validator,
    bytes calldata signatures,
    bytes32[] calldata proof
  ) external override {
    if (validatorsRegistry.get_deposit_root() != validatorsRegistryRoot) {
      revert InvalidValidatorsRegistryRoot();
    }
    if (!registry.vaults(vault)) revert InvalidVault();

    // verify signers approved registration
    signers.verifySignatures(
      keccak256(
        abi.encode(_registerValidatorTypeHash, validatorsRegistryRoot, vault, keccak256(validator))
      ),
      signatures
    );

    // collateralize vault
    if (rewards[vault].nonce == 0) {
      rewards[vault] = RewardSync({nonce: rewardsNonce + 1, reward: 0});
    }

    emit ValidatorRegistered(vault, validatorsRegistryRoot, validator, signatures);

    // register validator
    IEthVault(vault).registerValidator(validator, proof);
  }

  /// @inheritdoc IEthOracle
  function registerValidators(
    address vault,
    bytes32 validatorsRegistryRoot,
    bytes[] calldata validators,
    bytes calldata signatures,
    bool[] calldata proofFlags,
    bytes32[] calldata proof
  ) external override {
    if (validatorsRegistry.get_deposit_root() != validatorsRegistryRoot) {
      revert InvalidValidatorsRegistryRoot();
    }
    if (!registry.vaults(vault)) revert InvalidVault();

    // verify signers approved registration
    signers.verifySignatures(
      keccak256(
        abi.encode(
          _registerValidatorsTypeHash,
          validatorsRegistryRoot,
          vault,
          keccak256(abi.encode(validators))
        )
      ),
      signatures
    );

    // collateralize vault
    if (rewards[vault].nonce == 0) {
      rewards[vault] = RewardSync({nonce: rewardsNonce + 1, reward: 0});
    }

    emit ValidatorsRegistered(vault, validatorsRegistryRoot, validators, signatures);

    // register validators
    IEthVault(vault).registerValidators(validators, proofFlags, proof);
  }
}
