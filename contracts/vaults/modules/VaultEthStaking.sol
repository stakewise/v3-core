// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {ReentrancyGuardUpgradeable} from '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {IEthValidatorsRegistry} from '../../interfaces/IEthValidatorsRegistry.sol';
import {IKeeperRewards} from '../../interfaces/IKeeperRewards.sol';
import {IVaultEthStaking} from '../../interfaces/IVaultEthStaking.sol';
import {IMevEscrow} from '../../interfaces/IMevEscrow.sol';
import {VaultValidators} from '../modules/VaultValidators.sol';
import {VaultToken} from '../modules/VaultToken.sol';
import {VaultState} from '../modules/VaultState.sol';
import {VaultEnterExit} from '../modules/VaultEnterExit.sol';

// Custom errors
error InvalidSecurityDeposit();

/**
 * @title VaultEthStaking
 * @author StakeWise
 * @notice Defines the Ethereum staking functionality for the Vault
 */
abstract contract VaultEthStaking is
  Initializable,
  ReentrancyGuardUpgradeable,
  VaultToken,
  VaultState,
  VaultValidators,
  VaultEnterExit,
  IVaultEthStaking
{
  // @inheritdoc IVaultEthStaking
  uint256 public constant override securityDeposit = 1e9;

  /// @inheritdoc IVaultEthStaking
  // slither-disable-next-line uninitialized-state
  IMevEscrow public override mevEscrow;

  /// @inheritdoc IVaultEthStaking
  function deposit(
    address receiver,
    address referrer
  ) public payable virtual override returns (uint256 shares) {
    return _deposit(receiver, msg.value, referrer);
  }

  /// @inheritdoc IVaultEthStaking
  function updateStateAndDeposit(
    address receiver,
    address referrer,
    IKeeperRewards.HarvestParams calldata harvestParams
  ) public payable virtual override returns (uint256 shares) {
    updateState(harvestParams);
    return deposit(receiver, referrer);
  }

  /**
   * @dev Function for receiving validator withdrawals
   */
  receive() external payable {}

  /// @inheritdoc VaultValidators
  function _registerSingleValidator(bytes calldata validator) internal override {
    bytes calldata publicKey = validator[:48];
    IEthValidatorsRegistry(validatorsRegistry).deposit{value: _validatorDeposit()}(
      publicKey,
      withdrawalCredentials(),
      validator[48:144],
      bytes32(validator[144:_validatorLength])
    );

    emit ValidatorRegistered(publicKey);
  }

  /// @inheritdoc VaultValidators
  function _registerMultipleValidators(
    bytes calldata validators,
    uint256[] calldata indexes
  ) internal override returns (bytes32[] memory leaves) {
    // SLOAD to memory
    uint256 currentValIndex = validatorIndex;

    uint256 startIndex;
    uint256 endIndex;
    bytes calldata validator;
    bytes calldata publicKey;
    leaves = new bytes32[](indexes.length);
    bytes memory withdrawalCreds = withdrawalCredentials();
    for (uint256 i = 0; i < indexes.length; ) {
      unchecked {
        // cannot realistically overflow
        endIndex += _validatorLength;
      }
      validator = validators[startIndex:endIndex];
      leaves[indexes[i]] = keccak256(
        bytes.concat(keccak256(abi.encode(validator, currentValIndex)))
      );
      publicKey = validator[:48];
      // slither-disable-next-line arbitrary-send-eth
      IEthValidatorsRegistry(validatorsRegistry).deposit{value: _validatorDeposit()}(
        publicKey,
        withdrawalCreds,
        validator[48:144],
        bytes32(validator[144:_validatorLength])
      );
      startIndex = endIndex;
      unchecked {
        // cannot realistically overflow
        ++i;
        ++currentValIndex;
      }
      emit ValidatorRegistered(publicKey);
    }
  }

  /// @inheritdoc VaultToken
  function _vaultAssets() internal view override returns (uint256) {
    return address(this).balance;
  }

  /// @inheritdoc VaultToken
  function _transferVaultAssets(address receiver, uint256 assets) internal override nonReentrant {
    return Address.sendValue(payable(receiver), assets);
  }

  /// @inheritdoc VaultState
  function _harvestAssets(
    IKeeperRewards.HarvestParams calldata harvestParams
  ) internal override returns (int256) {
    return IKeeperRewards(keeper).harvest(harvestParams) + int256(mevEscrow.withdraw());
  }

  /// @inheritdoc VaultValidators
  function _validatorDeposit() internal pure override returns (uint256) {
    return 32 ether;
  }

  /**
   * @dev Initializes the VaultEthStaking contract
   * @param _mevEscrow The address of the MEV escrow
   */
  function __VaultEthStaking_init(address _mevEscrow) internal onlyInitializing {
    __ReentrancyGuard_init();
    mevEscrow = IMevEscrow(_mevEscrow);

    if (msg.value < securityDeposit) revert InvalidSecurityDeposit();
    _deposit(address(this), msg.value, address(0));
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
