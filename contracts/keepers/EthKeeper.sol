// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {Keeper} from '../abstract/Keeper.sol';
import {IEthKeeper} from '../interfaces/IEthKeeper.sol';
import {IValidatorsRegistry} from '../interfaces/IValidatorsRegistry.sol';
import {IRegistry} from '../interfaces/IRegistry.sol';
import {IOracles} from '../interfaces/IOracles.sol';
import {IEthVault} from '../interfaces/IEthVault.sol';

/**
 * @title EthKeeper
 * @author StakeWise
 * @notice Defines the functionality for registering validators for the Ethereum Vaults
 */
contract EthKeeper is Keeper, IEthKeeper {
  bytes32 internal constant _registerValidatorTypeHash =
    keccak256('EthKeeper(bytes32 validatorsRegistryRoot,address vault,bytes32 validator)');
  bytes32 internal constant _registerValidatorsTypeHash =
    keccak256('EthKeeper(bytes32 validatorsRegistryRoot,address vault,bytes32 validators)');

  /// @inheritdoc IEthKeeper
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IValidatorsRegistry public immutable override validatorsRegistry;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param _oracles The address of the Oracles contract
   * @param _registry The address of the Registry contract
   * @param _validatorsRegistry The address of the Validators Registry contract
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    IOracles _oracles,
    IRegistry _registry,
    IValidatorsRegistry _validatorsRegistry
  ) Keeper(_oracles, _registry) {
    validatorsRegistry = _validatorsRegistry;
  }

  /// @inheritdoc IEthKeeper
  function initialize(address _owner) external override initializer {
    __Keeper_init(_owner);
  }

  /// @inheritdoc IEthKeeper
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

    // verify all oracles approved registration
    oracles.verifyAllSignatures(
      keccak256(
        abi.encode(_registerValidatorTypeHash, validatorsRegistryRoot, vault, keccak256(validator))
      ),
      signatures
    );

    _collateralize(vault);

    emit ValidatorsRegistered(
      vault,
      validatorsRegistryRoot,
      validator,
      signatures,
      block.timestamp
    );

    // register validator
    IEthVault(vault).registerValidator(validator, proof);
  }

  /// @inheritdoc IEthKeeper
  function registerValidators(
    address vault,
    bytes32 validatorsRegistryRoot,
    bytes calldata validators,
    bytes calldata signatures,
    bool[] calldata proofFlags,
    bytes32[] calldata proof
  ) external override {
    if (validatorsRegistry.get_deposit_root() != validatorsRegistryRoot) {
      revert InvalidValidatorsRegistryRoot();
    }
    if (!registry.vaults(vault)) revert InvalidVault();

    // verify all oracles approved registration
    oracles.verifyAllSignatures(
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

    _collateralize(vault);

    emit ValidatorsRegistered(
      vault,
      validatorsRegistryRoot,
      validators,
      signatures,
      block.timestamp
    );

    // register validators
    IEthVault(vault).registerValidators(validators, proofFlags, proof);
  }
}
