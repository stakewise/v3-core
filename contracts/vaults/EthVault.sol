// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {MerkleProof} from '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import {IVaultFactory} from '../interfaces/IVaultFactory.sol';
import {IVault} from '../interfaces/IVault.sol';
import {IEthVault} from '../interfaces/IEthVault.sol';
import {IFeesEscrow} from '../interfaces/IFeesEscrow.sol';
import {IEthValidatorsRegistry} from '../interfaces/IEthValidatorsRegistry.sol';
import {Vault} from '../abstract/Vault.sol';
import {EthFeesEscrow} from './EthFeesEscrow.sol';

/**
 * @title EthVault
 * @author StakeWise
 * @notice Defines Vault functionality for staking on Ethereum
 */
contract EthVault is Vault, IEthVault {
  uint256 internal constant _validatorDeposit = 32 ether;

  /// @inheritdoc IVault
  IFeesEscrow public immutable override feesEscrow;

  IEthValidatorsRegistry internal immutable _validatorsRegistry;

  bytes32 internal immutable _withdrawalCredentials;

  /// @dev Constructor
  constructor() Vault() {
    feesEscrow = IFeesEscrow(new EthFeesEscrow());
    _withdrawalCredentials = bytes32(abi.encodePacked(bytes1(0x01), bytes11(0x0), address(this)));
    _validatorsRegistry = IEthValidatorsRegistry(IVaultFactory(msg.sender).validatorsRegistry());
  }

  /// @inheritdoc IEthVault
  function deposit(address receiver) external payable override returns (uint256 shares) {
    return _deposit(receiver, msg.value);
  }

  /// @inheritdoc IVault
  function registerValidator(bytes calldata validator, bytes32[] calldata proof)
    external
    override
    onlyKeeper
  {
    if (availableAssets() < _validatorDeposit) revert InsufficientAvailableAssets();
    if (
      validator.length != 176 ||
      validatorsRoot != MerkleProof.processProofCalldata(proof, keccak256(validator[:144]))
    ) {
      revert InvalidValidator();
    }

    bytes calldata publicKey = validator[:48];
    _validatorsRegistry.deposit{value: _validatorDeposit}(
      publicKey,
      abi.encode(_withdrawalCredentials),
      validator[48:144],
      bytes32(validator[144:176])
    );

    emit ValidatorRegistered(publicKey);
  }

  /// @inheritdoc IVault
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
      _validatorsRegistry.deposit{value: _validatorDeposit}(
        publicKey,
        abi.encode(_withdrawalCredentials),
        validator[48:144],
        bytes32(validator[144:176])
      );
      unchecked {
        ++i;
      }
      emit ValidatorRegistered(publicKey);
    }
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

  /// @inheritdoc Vault
  function _claimVaultRewards() internal override returns (uint256) {
    return feesEscrow.withdraw();
  }
}
