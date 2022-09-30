// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {MerkleProof} from '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import {IVaultFactory} from '../interfaces/IVaultFactory.sol';
import {IEthVault} from '../interfaces/IEthVault.sol';
import {IFeesEscrow} from '../interfaces/IFeesEscrow.sol';
import {IEthValidatorsRegistry} from '../interfaces/IEthValidatorsRegistry.sol';
import {Vault} from '../abstract/Vault.sol';
import {EthFeesEscrow} from './EthFeesEscrow.sol';

/// Custom errors
// TODO: check gas when under interface
error InvalidValidator();

/**
 * @title EthVault
 * @author StakeWise
 * @notice Defines Vault functionality for staking on Ethereum
 */
contract EthVault is Vault, IEthVault {
  uint256 internal constant _validatorDeposit = 32 ether;

  /// @inheritdoc IEthVault
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

  function registerValidators(bytes[] calldata validators, bytes32[] calldata proof)
    external
    onlyKeeper
  {
    // TODO: check gas without extra variable
    uint256 validatorsCount = validators.length;
    if (validatorsCount * _validatorDeposit > availableAssets()) {
      revert InsufficientAvailableAssets();
    }

    for (uint256 i = 0; i < validatorsCount; ) {
      bytes calldata validator = validators[i];
      if (
        validator.length != 176 ||
        validatorsRoot != MerkleProof.processProofCalldata(proof, keccak256(validator[:144]))
      ) {
        revert InvalidValidator();
      }
      _validatorsRegistry.deposit{value: _validatorDeposit}(
        validator[:48],
        abi.encode(_withdrawalCredentials),
        validator[48:144],
        bytes32(validator[144:176])
      );
      unchecked {
        ++i;
      }
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
