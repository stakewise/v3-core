// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {MerkleProof} from '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import {IVault} from '../interfaces/IVault.sol';
import {IEthVault} from '../interfaces/IEthVault.sol';
import {IFeesEscrow} from '../interfaces/IFeesEscrow.sol';
import {IEthValidatorsRegistry} from '../interfaces/IEthValidatorsRegistry.sol';
import {IRegistry} from '../interfaces/IRegistry.sol';
import {IKeeper} from '../interfaces/IKeeper.sol';
import {Vault} from '../abstract/Vault.sol';
import {EthFeesEscrow} from './EthFeesEscrow.sol';

/**
 * @title EthVault
 * @author StakeWise
 * @notice Defines Vault functionality for staking on Ethereum
 */
contract EthVault is Vault, IEthVault {
  uint256 internal constant _validatorDeposit = 32 ether;

  /// @inheritdoc IEthVault
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IEthValidatorsRegistry public immutable override validatorsRegistry;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param _keeper The address of the Keeper that can harvest Vault's rewards
   * @param _registry The address of the Registry contract
   * @param _validatorsRegistry The address used for registering Vault's validators
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    IKeeper _keeper,
    IRegistry _registry,
    IEthValidatorsRegistry _validatorsRegistry
  ) Vault(_keeper, _registry) {
    validatorsRegistry = _validatorsRegistry;
  }

  /// @inheritdoc IEthVault
  function initialize(IVault.InitParams memory params) external override initializer {
    __EthVault_init(params);
  }

  /// @inheritdoc IEthVault
  function deposit(address receiver) external payable override returns (uint256 shares) {
    return _deposit(receiver, msg.value);
  }

  /// @inheritdoc IEthVault
  function registerValidator(bytes calldata validator, bytes32[] calldata proof)
    external
    override
    onlyKeeper
  {
    if (availableAssets() < _validatorDeposit) revert InsufficientAvailableAssets();
    if (
      validator.length != 176 ||
      !MerkleProof.verifyCalldata(proof, validatorsRoot, keccak256(validator[:144]))
    ) {
      revert InvalidValidator();
    }

    bytes calldata publicKey = validator[:48];
    validatorsRegistry.deposit{value: _validatorDeposit}(
      publicKey,
      withdrawalCredentials(),
      validator[48:144],
      bytes32(validator[144:176])
    );

    emit ValidatorRegistered(publicKey);
  }

  /// @inheritdoc IEthVault
  function registerValidators(
    bytes[] calldata validators,
    bool[] calldata proofFlags,
    bytes32[] calldata proof
  ) external override onlyKeeper {
    if (availableAssets() < _validatorDeposit * validators.length) {
      revert InsufficientAvailableAssets();
    }

    bytes calldata validator;
    bytes calldata publicKey;
    bytes32[] memory leaves = new bytes32[](validators.length);
    bytes memory withdrawalCreds = withdrawalCredentials();
    for (uint256 i = 0; i < validators.length; ) {
      validator = validators[i];
      if (validator.length != 176) revert InvalidValidator();
      leaves[i] = keccak256(validator[:144]);

      publicKey = validator[:48];
      validatorsRegistry.deposit{value: _validatorDeposit}(
        publicKey,
        withdrawalCreds,
        validator[48:144],
        bytes32(validator[144:176])
      );
      unchecked {
        ++i;
      }
      emit ValidatorRegistered(publicKey);
    }

    if (!MerkleProof.multiProofVerifyCalldata(proof, proofFlags, validatorsRoot, leaves)) {
      revert InvalidProof();
    }
  }

  /// @inheritdoc IVault
  function withdrawalCredentials() public view override returns (bytes memory) {
    return abi.encodePacked(bytes1(0x01), bytes11(0x0), address(this));
  }

  /**
   * @dev Function for receiving validator withdrawals
   */
  receive() external payable {}

  /// @inheritdoc Vault
  function _vaultAssets() internal view override returns (uint256) {
    return address(this).balance;
  }

  /// @inheritdoc Vault
  function _transferAssets(address receiver, uint256 assets) internal override {
    return Address.sendValue(payable(receiver), assets);
  }

  /**
   * @dev Initializes the EthVault contract
   * @param initParams The Vault's initialization parameters
   */
  function __EthVault_init(IVault.InitParams memory initParams) internal onlyInitializing {
    __Vault_init(initParams);
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
