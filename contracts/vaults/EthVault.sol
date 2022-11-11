// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {MerkleProof} from '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import {IBaseVault} from '../interfaces/IBaseVault.sol';
import {IEthVault} from '../interfaces/IEthVault.sol';
import {IFeesEscrow} from '../interfaces/IFeesEscrow.sol';
import {IEthValidatorsRegistry} from '../interfaces/IEthValidatorsRegistry.sol';
import {IRegistry} from '../interfaces/IRegistry.sol';
import {IBaseKeeper} from '../interfaces/IBaseKeeper.sol';
import {BaseVault} from './BaseVault.sol';
import {EthFeesEscrow} from './EthFeesEscrow.sol';

/**
 * @title EthVault
 * @author StakeWise
 * @notice Defines Vault functionality for staking on Ethereum
 */
contract EthVault is BaseVault, IEthVault {
  uint256 internal constant _validatorDeposit = 32 ether;
  uint256 internal constant _validatorLength = 176;

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
    IBaseKeeper _keeper,
    IRegistry _registry,
    IEthValidatorsRegistry _validatorsRegistry
  ) BaseVault(_keeper, _registry) {
    validatorsRegistry = _validatorsRegistry;
  }

  /// @inheritdoc IEthVault
  function initialize(IBaseVault.InitParams memory params) external override initializer {
    __EthVault_init(params);
  }

  /// @inheritdoc IEthVault
  function deposit(address receiver) external payable override returns (uint256 shares) {
    return _deposit(receiver, msg.value);
  }

  /// @inheritdoc IEthVault
  function registerValidator(
    bytes calldata validator,
    bytes32[] calldata proof
  ) external override onlyKeeper {
    if (availableAssets() < _validatorDeposit) revert InsufficientAvailableAssets();
    if (
      !MerkleProof.verifyCalldata(
        proof,
        validatorsRoot,
        keccak256(bytes.concat(keccak256(abi.encode(validator))))
      )
    ) {
      revert InvalidValidator();
    }

    bytes calldata publicKey = validator[:48];
    validatorsRegistry.deposit{value: _validatorDeposit}(
      publicKey,
      withdrawalCredentials(),
      validator[48:144],
      bytes32(validator[144:_validatorLength])
    );

    emit ValidatorRegistered(publicKey);
  }

  /// @inheritdoc IEthVault
  function registerValidators(
    bytes calldata validators,
    bool[] calldata proofFlags,
    bytes32[] calldata proof
  ) external override onlyKeeper {
    uint256 validatorsCount = validators.length / _validatorLength;
    if (availableAssets() < _validatorDeposit * validatorsCount) {
      revert InsufficientAvailableAssets();
    }

    uint256 endIdx;
    uint256 leavesCount;
    bytes calldata validator;
    bytes calldata publicKey;
    bytes32[] memory leaves = new bytes32[](validatorsCount);
    bytes memory withdrawalCreds = withdrawalCredentials();
    for (uint256 startIdx = 0; startIdx < validators.length; ) {
      unchecked {
        // cannot overflow as it is capped with staked asset total supply
        endIdx = startIdx + _validatorLength;
      }
      validator = validators[startIdx:endIdx];
      leaves[leavesCount] = keccak256(bytes.concat(keccak256(abi.encode(validator))));
      publicKey = validator[:48];
      validatorsRegistry.deposit{value: _validatorDeposit}(
        publicKey,
        withdrawalCreds,
        validator[48:144],
        bytes32(validator[144:176])
      );
      startIdx = endIdx;
      unchecked {
        ++leavesCount;
      }
      emit ValidatorRegistered(publicKey);
    }

    if (!MerkleProof.multiProofVerifyCalldata(proof, proofFlags, validatorsRoot, leaves)) {
      revert InvalidProof();
    }
  }

  /// @inheritdoc IBaseVault
  function withdrawalCredentials() public view override returns (bytes memory) {
    return abi.encodePacked(bytes1(0x01), bytes11(0x0), address(this));
  }

  /**
   * @dev Function for receiving validator withdrawals
   */
  receive() external payable {}

  /// @inheritdoc BaseVault
  function _vaultAssets() internal view override returns (uint256) {
    return address(this).balance;
  }

  /// @inheritdoc BaseVault
  function _transferAssets(address receiver, uint256 assets) internal override nonReentrant {
    return Address.sendValue(payable(receiver), assets);
  }

  /**
   * @dev Initializes the EthVault contract
   * @param initParams The Vault's initialization parameters
   */
  function __EthVault_init(IBaseVault.InitParams memory initParams) internal onlyInitializing {
    __BaseVault_init(initParams);
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
