// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IEigenVault} from '../../interfaces/IEigenVault.sol';
import {IEthVaultFactory} from '../../interfaces/IEthVaultFactory.sol';
import {Multicall} from '../../base/Multicall.sol';
import {VaultValidators} from '../modules/VaultValidators.sol';
import {VaultAdmin} from '../modules/VaultAdmin.sol';
import {VaultFee} from '../modules/VaultFee.sol';
import {VaultVersion, IVaultVersion} from '../modules/VaultVersion.sol';
import {VaultImmutables} from '../modules/VaultImmutables.sol';
import {VaultState} from '../modules/VaultState.sol';
import {VaultEnterExit, IVaultEnterExit} from '../modules/VaultEnterExit.sol';
import {VaultEthStaking} from '../modules/VaultEthStaking.sol';
import {VaultMev} from '../modules/VaultMev.sol';
import {VaultEigenStaking} from '../modules/VaultEigenStaking.sol';

/**
 * @title EigenVault
 * @author StakeWise
 * @notice Defines the EigenLayer staking Vault
 */
contract EigenVault is
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
  VaultEigenStaking,
  Multicall,
  IEigenVault
{
  uint8 private constant _version = 2;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param _keeper The address of the Keeper contract
   * @param _vaultsRegistry The address of the VaultsRegistry contract
   * @param _validatorsRegistry The contract address used for registering validators in beacon chain
   * @param sharedMevEscrow The address of the shared MEV escrow
   * @param depositDataManager The address of the DepositDataManager contract
   * @param eigenDelegationManager The address of the EigenDelegationManager contract
   * @param eigenDelayedWithdrawalRouter The address of the EigenDelayedWithdrawalRouter contract
   * @param eigenPodProxyFactory The address of the EigenPodProxyFactory contract
   * @param exitingAssetsClaimDelay The delay after which the assets can be claimed after exiting from staking
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address _keeper,
    address _vaultsRegistry,
    address _validatorsRegistry,
    address sharedMevEscrow,
    address depositDataManager,
    address eigenPodManager,
    address eigenDelegationManager,
    address eigenDelayedWithdrawalRouter,
    address eigenPodProxyFactory,
    uint256 exitingAssetsClaimDelay
  )
    VaultImmutables(_keeper, _vaultsRegistry, _validatorsRegistry)
    VaultValidators(depositDataManager)
    VaultEnterExit(exitingAssetsClaimDelay)
    VaultMev(sharedMevEscrow)
    VaultEigenStaking(
      eigenPodManager,
      eigenDelegationManager,
      eigenDelayedWithdrawalRouter,
      eigenPodProxyFactory
    )
  {
    _disableInitializers();
  }

  /// @inheritdoc IEigenVault
  function initialize(
    bytes calldata params
  ) external payable virtual override reinitializer(_version) {
    // initialize deployed vault
    __EigenVault_init(
      IEthVaultFactory(msg.sender).vaultAdmin(),
      IEthVaultFactory(msg.sender).ownMevEscrow(),
      abi.decode(params, (EigenVaultInitParams))
    );
  }

  /// @inheritdoc VaultVersion
  function vaultId() public pure virtual override(IVaultVersion, VaultVersion) returns (bytes32) {
    return keccak256('EigenVault');
  }

  /// @inheritdoc IVaultVersion
  function version() public pure virtual override(IVaultVersion, VaultVersion) returns (uint8) {
    return _version;
  }

  /// @inheritdoc VaultValidators
  function _registerSingleValidator(
    bytes calldata validator
  ) internal virtual override(VaultValidators, VaultEthStaking, VaultEigenStaking) {
    return super._registerSingleValidator(validator);
  }

  /// @inheritdoc VaultValidators
  function _registerMultipleValidators(
    bytes calldata validators
  ) internal override(VaultValidators, VaultEthStaking, VaultEigenStaking) {
    return super._registerMultipleValidators(validators);
  }

  /// @inheritdoc VaultEthStaking
  function _withdrawalCredentials()
    internal
    view
    override(VaultEthStaking, VaultEigenStaking)
    returns (bytes memory)
  {
    return super._withdrawalCredentials();
  }

  /// @inheritdoc VaultValidators
  function _validatorLength()
    internal
    pure
    virtual
    override(VaultValidators, VaultEthStaking, VaultEigenStaking)
    returns (uint256)
  {
    return super._validatorLength();
  }

  /**
   * @dev Initializes the EigenVault contract
   * @param admin The address of the admin of the Vault
   * @param ownMevEscrow The address of the MEV escrow owned by the Vault. Zero address if shared MEV escrow is used.
   * @param params The decoded parameters for initializing the EigenVault contract
   */
  function __EigenVault_init(
    address admin,
    address ownMevEscrow,
    EigenVaultInitParams memory params
  ) internal onlyInitializing {
    __VaultAdmin_init(admin, params.metadataIpfsHash);
    // fee recipient is initially set to admin address
    __VaultFee_init(admin, params.feePercent);
    __VaultState_init(params.capacity);
    __VaultValidators_init();
    __VaultMev_init(ownMevEscrow);
    __VaultEthStaking_init();
    __VaultEigenStaking_init();
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
