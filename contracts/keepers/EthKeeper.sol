// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {IEthKeeper} from '../interfaces/IEthKeeper.sol';
import {IValidatorsRegistry} from '../interfaces/IValidatorsRegistry.sol';
import {IRegistry} from '../interfaces/IRegistry.sol';
import {IOracles} from '../interfaces/IOracles.sol';
import {IEthVault} from '../interfaces/IEthVault.sol';
import {BaseKeeper} from './BaseKeeper.sol';

/**
 * @title EthKeeper
 * @author StakeWise
 * @notice Defines the functionality for registering validators for the Ethereum Vaults
 */
contract EthKeeper is BaseKeeper, IEthKeeper {
  bytes32 internal constant _registerValidatorsTypeHash =
    keccak256(
      'EthKeeper(bytes32 validatorsRegistryRoot,address vault,bytes32 validators,bytes32 exitSignaturesIpfsHash)'
    );

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
  ) BaseKeeper(_oracles, _registry) {
    validatorsRegistry = _validatorsRegistry;
  }

  /// @inheritdoc IEthKeeper
  function initialize(address _owner) external override initializer {
    __BaseKeeper_init(_owner);
  }

  /// @inheritdoc IEthKeeper
  function registerValidator(ValidatorRegistrationData calldata data) external override {
    if (validatorsRegistry.get_deposit_root() != data.validatorsRegistryRoot) {
      revert InvalidValidatorsRegistryRoot();
    }
    if (!registry.vaults(data.vault)) revert InvalidVault();

    // verify all oracles approved registration
    oracles.verifyAllSignatures(
      keccak256(
        abi.encode(
          _registerValidatorsTypeHash,
          data.validatorsRegistryRoot,
          data.vault,
          keccak256(data.validator),
          keccak256(bytes(data.exitSignatureIpfsHash))
        )
      ),
      data.signatures
    );

    _collateralize(data.vault);

    emit ValidatorsRegistered(
      data.vault,
      data.validator,
      data.exitSignatureIpfsHash,
      block.timestamp
    );

    // register validator
    IEthVault(data.vault).registerValidator(data.validator, data.proof);
  }

  /// @inheritdoc IEthKeeper
  function registerValidators(ValidatorsRegistrationData calldata data) external override {
    if (validatorsRegistry.get_deposit_root() != data.validatorsRegistryRoot) {
      revert InvalidValidatorsRegistryRoot();
    }
    if (!registry.vaults(data.vault)) revert InvalidVault();

    // verify all oracles approved registration
    oracles.verifyAllSignatures(
      keccak256(
        abi.encode(
          _registerValidatorsTypeHash,
          data.validatorsRegistryRoot,
          data.vault,
          keccak256(data.validators),
          keccak256(bytes(data.exitSignaturesIpfsHash))
        )
      ),
      data.signatures
    );

    _collateralize(data.vault);

    emit ValidatorsRegistered(
      data.vault,
      data.validators,
      data.exitSignaturesIpfsHash,
      block.timestamp
    );

    // register validators
    IEthVault(data.vault).registerValidators(
      data.validators,
      data.indexes,
      data.proofFlags,
      data.proof
    );
  }
}
