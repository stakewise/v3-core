// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {MerkleProof} from '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import {IVault} from '../interfaces/IVault.sol';
import {IVaultValidators} from '../interfaces/IVaultValidators.sol';
import {IEthVault} from '../interfaces/IEthVault.sol';
import {IFeesEscrow} from '../interfaces/IFeesEscrow.sol';
import {IEthValidatorsRegistry} from '../interfaces/IEthValidatorsRegistry.sol';
import {IRegistry} from '../interfaces/IRegistry.sol';
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

  /// @inheritdoc IVaultValidators
  IFeesEscrow public override feesEscrow;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param _keeper The keeper address that can harvest Vault's rewards
   * @param _registry The address of the Registry
   * @param _validatorsRegistry The address used for registering Vault's validators
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address _keeper,
    IRegistry _registry,
    IEthValidatorsRegistry _validatorsRegistry
  ) Vault(_keeper, _registry) {
    validatorsRegistry = _validatorsRegistry;
  }

  /**
   * @dev Initializes the EthVault contract
   * @param _name The name of the ERC20 token
   * @param _symbol The symbol of the ERC20 token
   * @param _maxTotalAssets The max total assets that can be staked into the Vault
   * @param _operator The address of the Vault operator
   * @param _feePercent The fee percent that is charged by the Vault operator
   */
  function initialize(
    string memory _name,
    string memory _symbol,
    uint256 _maxTotalAssets,
    address _operator,
    uint16 _feePercent
  ) external virtual initializer {
    __EthVault_init(_name, _symbol, _maxTotalAssets, _operator, _feePercent);
  }

  /// @inheritdoc IEthVault
  function deposit(address receiver) external payable override returns (uint256 shares) {
    return _deposit(receiver, msg.value);
  }

  /// @inheritdoc IVaultValidators
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

  /// @inheritdoc IVaultValidators
  function registerValidators(bytes[] calldata validators, bytes32[][] calldata proofs)
    external
    override
    onlyKeeper
  {
    if (availableAssets() < _validatorDeposit * validators.length) {
      revert InsufficientAvailableAssets();
    }
    if (validators.length != proofs.length) revert InvalidProofsLength();

    bytes calldata validator;
    bytes calldata publicKey;
    for (uint256 i = 0; i < validators.length; ) {
      validator = validators[i];
      // TODO: update after https://github.com/OpenZeppelin/openzeppelin-contracts/issues/3743
      if (
        validator.length != 176 ||
        validatorsRoot != MerkleProof.processProofCalldata(proofs[i], keccak256(validator[:144]))
      ) {
        revert InvalidValidator();
      }
      publicKey = validator[:48];
      validatorsRegistry.deposit{value: _validatorDeposit}(
        publicKey,
        withdrawalCredentials(),
        validator[48:144],
        bytes32(validator[144:176])
      );
      unchecked {
        ++i;
      }
      emit ValidatorRegistered(publicKey);
    }
  }

  /// @inheritdoc IVaultValidators
  function withdrawalCredentials() public view override returns (bytes memory) {
    return abi.encodePacked(bytes1(0x01), bytes11(0x0), address(this));
  }

  /**
   * @dev Function for receiving validator withdrawals
   */
  receive() external payable {}

  /**
   * @dev Initializes the EthVault contract
   * @param _name The name of the ERC20 token
   * @param _symbol The symbol of the ERC20 token
   * @param _maxTotalAssets The max total assets that can be staked into the Vault
   * @param _operator The address of the Vault operator
   * @param _feePercent The fee percent that is charged by the Vault operator
   */
  function __EthVault_init(
    string memory _name,
    string memory _symbol,
    uint256 _maxTotalAssets,
    address _operator,
    uint16 _feePercent
  ) internal onlyInitializing {
    __Vault_init(_name, _symbol, _maxTotalAssets, _operator, _feePercent);

    // create fees escrow contract
    feesEscrow = IFeesEscrow(new EthFeesEscrow());
  }

  /// @inheritdoc Vault
  function _vaultAssets() internal view override returns (uint256) {
    return address(this).balance;
  }

  /// @inheritdoc Vault
  function _transferAssets(address receiver, uint256 assets) internal override {
    return Address.sendValue(payable(receiver), assets);
  }

  /// @inheritdoc Vault
  function _claimVaultRewards() internal override returns (uint256) {
    return feesEscrow.withdraw();
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
