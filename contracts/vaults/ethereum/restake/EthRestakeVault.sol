// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IEthRestakeVault} from '../../../interfaces/IEthRestakeVault.sol';
import {IEthVaultFactory} from '../../../interfaces/IEthVaultFactory.sol';
import {Multicall} from '../../../base/Multicall.sol';
import {VaultValidators} from '../../modules/VaultValidators.sol';
import {VaultAdmin} from '../../modules/VaultAdmin.sol';
import {VaultFee} from '../../modules/VaultFee.sol';
import {VaultVersion, IVaultVersion} from '../../modules/VaultVersion.sol';
import {VaultImmutables} from '../../modules/VaultImmutables.sol';
import {VaultState} from '../../modules/VaultState.sol';
import {VaultEnterExit, IVaultEnterExit} from '../../modules/VaultEnterExit.sol';
import {VaultMev} from '../../modules/VaultMev.sol';
import {VaultEthStaking} from '../../modules/VaultEthStaking.sol';
import {VaultEthRestaking} from '../../modules/VaultEthRestaking.sol';

/**
 * @title EthRestakeVault
 * @author StakeWise
 * @notice Defines the restaking Vault on Ethereum
 */
contract EthRestakeVault is
  VaultImmutables,
  Initializable,
  VaultAdmin,
  VaultVersion,
  VaultFee,
  VaultState,
  VaultValidators,
  VaultEnterExit,
  VaultMev,
  VaultEthStaking,
  VaultEthRestaking,
  Multicall,
  IEthRestakeVault
{
  using EnumerableSet for EnumerableSet.AddressSet;

  uint8 private constant _version = 2;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param _keeper The address of the Keeper contract
   * @param _vaultsRegistry The address of the VaultsRegistry contract
   * @param _validatorsRegistry The contract address used for registering validators in beacon chain
   * @param sharedMevEscrow The address of the shared MEV escrow
   * @param depositDataRegistry The address of the DepositDataRegistry contract
   * @param eigenPodOwnerImplementation The address of the EigenPodOwner implementation contract
   * @param exitingAssetsClaimDelay The delay after which the assets can be claimed after exiting from staking
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address _keeper,
    address _vaultsRegistry,
    address _validatorsRegistry,
    address sharedMevEscrow,
    address depositDataRegistry,
    address eigenPodOwnerImplementation,
    uint256 exitingAssetsClaimDelay
  )
    VaultImmutables(_keeper, _vaultsRegistry, _validatorsRegistry)
    VaultValidators(depositDataRegistry)
    VaultEnterExit(exitingAssetsClaimDelay)
    VaultMev(sharedMevEscrow)
    VaultEthRestaking(eigenPodOwnerImplementation)
  {
    _disableInitializers();
  }

  /// @inheritdoc IEthRestakeVault
  function initialize(
    bytes calldata params
  ) external payable virtual override reinitializer(_version) {
    // initialize deployed vault
    __EthRestakeVault_init(
      IEthVaultFactory(msg.sender).vaultAdmin(),
      IEthVaultFactory(msg.sender).ownMevEscrow(),
      abi.decode(params, (EthRestakeVaultInitParams))
    );
  }

  /// @inheritdoc IVaultEnterExit
  function enterExitQueue(
    uint256 shares,
    address receiver
  ) public virtual override(IVaultEnterExit, VaultEnterExit) returns (uint256 positionTicket) {
    return super.enterExitQueue(shares, receiver);
  }

  /// @inheritdoc VaultVersion
  function vaultId() public pure virtual override(IVaultVersion, VaultVersion) returns (bytes32) {
    return keccak256('EthRestakeVault');
  }

  /// @inheritdoc IVaultVersion
  function version() public pure virtual override(IVaultVersion, VaultVersion) returns (uint8) {
    return _version;
  }

  /// @inheritdoc VaultEthStaking
  receive() external payable virtual override {
    if (!_eigenPodOwners.contains(msg.sender)) {
      // if the sender is not an EigenPod owner, deposit the received assets
      _deposit(msg.sender, msg.value, address(0));
    }
  }

  /// @inheritdoc VaultValidators
  function _registerSingleValidator(
    bytes calldata validator
  ) internal virtual override(VaultValidators, VaultEthStaking, VaultEthRestaking) {
    return super._registerSingleValidator(validator);
  }

  /// @inheritdoc VaultValidators
  function _registerMultipleValidators(
    bytes calldata validators
  ) internal override(VaultValidators, VaultEthStaking, VaultEthRestaking) {
    return super._registerMultipleValidators(validators);
  }

  /// @inheritdoc VaultValidators
  function _validatorLength()
    internal
    pure
    virtual
    override(VaultValidators, VaultEthStaking, VaultEthRestaking)
    returns (uint256)
  {
    return super._validatorLength();
  }

  /**
   * @dev Initializes the EthRestakeVault contract
   * @param admin The address of the admin of the Vault
   * @param ownMevEscrow The address of the MEV escrow owned by the Vault. Zero address if shared MEV escrow is used.
   * @param params The decoded parameters for initializing the EthRestakeVault contract
   */
  function __EthRestakeVault_init(
    address admin,
    address ownMevEscrow,
    EthRestakeVaultInitParams memory params
  ) internal onlyInitializing {
    __VaultAdmin_init(admin, params.metadataIpfsHash);
    // fee recipient is initially set to admin address
    __VaultFee_init(admin, params.feePercent);
    __VaultState_init(params.capacity);
    __VaultValidators_init();
    __VaultMev_init(ownMevEscrow);
    __VaultEthStaking_init();
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
