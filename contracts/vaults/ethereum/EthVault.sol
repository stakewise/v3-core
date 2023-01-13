// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {ReentrancyGuardUpgradeable} from '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {IEthValidatorsRegistry} from '../../interfaces/IEthValidatorsRegistry.sol';
import {IMevEscrow} from '../../interfaces/IMevEscrow.sol';
import {IVaultVersion} from '../../interfaces/IVaultVersion.sol';
import {IEthVault} from '../../interfaces/IEthVault.sol';
import {IKeeperRewards} from '../../interfaces/IKeeperRewards.sol';
import {Multicall} from '../../base/Multicall.sol';
import {VaultValidators} from '../modules/VaultValidators.sol';
import {VaultAdmin} from '../modules/VaultAdmin.sol';
import {VaultFee} from '../modules/VaultFee.sol';
import {VaultVersion} from '../modules/VaultVersion.sol';
import {VaultImmutables} from '../modules/VaultImmutables.sol';
import {VaultToken} from '../modules/VaultToken.sol';
import {VaultState} from '../modules/VaultState.sol';
import {VaultEnterExit} from '../modules/VaultEnterExit.sol';

/**
 * @title EthVault
 * @author StakeWise
 * @notice Defines the Ethereum Vault common functionality
 */
contract EthVault is
  VaultImmutables,
  Initializable,
  ReentrancyGuardUpgradeable,
  VaultToken,
  VaultAdmin,
  VaultVersion,
  VaultFee,
  VaultState,
  VaultValidators,
  VaultEnterExit,
  Multicall,
  IEthVault
{
  bytes32 private constant _VAULT_ID = keccak256('EthVault');

  /// @inheritdoc IEthVault
  IMevEscrow public override mevEscrow;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param _keeper The address of the Keeper contract
   * @param _vaultsRegistry The address of the VaultsRegistry contract
   * @param _validatorsRegistry The contract address used for registering validators in beacon chain
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address _keeper,
    address _vaultsRegistry,
    address _validatorsRegistry
  ) VaultImmutables(_keeper, _vaultsRegistry, _validatorsRegistry) {
    _disableInitializers();
  }

  /// @inheritdoc IEthVault
  function initialize(bytes calldata initParams) external virtual override initializer {
    EthVaultInitParams memory params = abi.decode(initParams, (EthVaultInitParams));
    __ReentrancyGuard_init();
    __VaultToken_init(params.name, params.symbol, params.capacity);
    __VaultAdmin_init(params.admin, params.metadataIpfsHash);
    // fee recipient is initially set to admin address
    __VaultFee_init(params.admin, params.feePercent);
    __VaultValidators_init(params.validatorsRoot, params.validatorsIpfsHash);

    mevEscrow = IMevEscrow(params.mevEscrow);
  }

  /// @inheritdoc IEthVault
  function deposit(address receiver) external payable virtual override returns (uint256 shares) {
    return _deposit(receiver, msg.value);
  }

  /// @inheritdoc IEthVault
  function updateStateAndDeposit(
    address receiver,
    IKeeperRewards.HarvestParams calldata harvestParams
  ) external payable virtual override returns (uint256 shares) {
    updateState(harvestParams);
    return _deposit(receiver, msg.value);
  }

  /**
   * @dev Function for receiving validator withdrawals
   */
  receive() external payable {}

  /// @inheritdoc VaultValidators
  function _registerSingleValidator(bytes calldata validator) internal override {
    bytes calldata publicKey = validator[:48];
    IEthValidatorsRegistry(validatorsRegistry).deposit{value: _validatorDeposit}(
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
      IEthValidatorsRegistry(validatorsRegistry).deposit{value: _validatorDeposit}(
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
    return super._harvestAssets(harvestParams) + int256(mevEscrow.withdraw());
  }

  /// @inheritdoc VaultVersion
  function vaultId() public pure override(IVaultVersion, VaultVersion) returns (bytes32) {
    return _VAULT_ID;
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
