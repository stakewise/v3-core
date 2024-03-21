// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IEigenErc20Vault} from '../../interfaces/IEigenErc20Vault.sol';
import {IEthVaultFactory} from '../../interfaces/IEthVaultFactory.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Multicall} from '../../base/Multicall.sol';
import {ERC20Upgradeable} from '../../base/ERC20Upgradeable.sol';
import {VaultValidators} from '../modules/VaultValidators.sol';
import {VaultAdmin} from '../modules/VaultAdmin.sol';
import {VaultFee} from '../modules/VaultFee.sol';
import {VaultVersion, IVaultVersion} from '../modules/VaultVersion.sol';
import {VaultImmutables} from '../modules/VaultImmutables.sol';
import {VaultState} from '../modules/VaultState.sol';
import {VaultEnterExit, IVaultEnterExit} from '../modules/VaultEnterExit.sol';
import {VaultEthStaking} from '../modules/VaultEthStaking.sol';
import {VaultMev} from '../modules/VaultMev.sol';
import {VaultToken} from '../modules/VaultToken.sol';
import {VaultEigenStaking} from '../modules/VaultEigenStaking.sol';

/**
 * @title EigenErc20Vault
 * @author StakeWise
 * @notice Defines the EigenLayer staking Vault with ERC-20 token
 */
contract EigenErc20Vault is
  VaultImmutables,
  Initializable,
  VaultAdmin,
  VaultVersion,
  VaultFee,
  VaultState,
  VaultValidators,
  VaultEnterExit,
  VaultMev,
  VaultToken,
  VaultEthStaking,
  VaultEigenStaking,
  Multicall,
  IEigenErc20Vault
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

  /// @inheritdoc IEigenErc20Vault
  function initialize(
    bytes calldata params
  ) external payable virtual override reinitializer(_version) {
    // initialize deployed vault
    __EigenErc20Vault_init(
      IEthVaultFactory(msg.sender).vaultAdmin(),
      IEthVaultFactory(msg.sender).ownMevEscrow(),
      abi.decode(params, (EigenErc20VaultInitParams))
    );
  }

  /// @inheritdoc IVaultVersion
  function vaultId() public pure virtual override(IVaultVersion, VaultVersion) returns (bytes32) {
    return keccak256('EigenErc20Vault');
  }

  /// @inheritdoc IVaultVersion
  function version() public pure virtual override(IVaultVersion, VaultVersion) returns (uint8) {
    return _version;
  }

  /// @inheritdoc VaultState
  function _updateExitQueue()
    internal
    virtual
    override(VaultState, VaultToken)
    returns (uint256 burnedShares)
  {
    return super._updateExitQueue();
  }

  /// @inheritdoc VaultState
  function _mintShares(
    address owner,
    uint256 shares
  ) internal virtual override(VaultState, VaultToken) {
    super._mintShares(owner, shares);
  }

  /// @inheritdoc VaultState
  function _burnShares(
    address owner,
    uint256 shares
  ) internal virtual override(VaultState, VaultToken) {
    super._burnShares(owner, shares);
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
   * @dev Initializes the EigenErc20Vault contract
   * @param admin The address of the admin of the Vault
   * @param ownMevEscrow The address of the MEV escrow owned by the Vault. Zero address if shared MEV escrow is used.
   * @param params The decoded parameters for initializing the EigenErc20Vault contract
   */
  function __EigenErc20Vault_init(
    address admin,
    address ownMevEscrow,
    EigenErc20VaultInitParams memory params
  ) internal onlyInitializing {
    __VaultAdmin_init(admin, params.metadataIpfsHash);
    // fee recipient is initially set to admin address
    __VaultFee_init(admin, params.feePercent);
    __VaultState_init(params.capacity);
    __VaultValidators_init();
    __VaultMev_init(ownMevEscrow);
    __VaultToken_init(params.name, params.symbol);
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
