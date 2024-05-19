// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IEthFoxVault} from '../../../interfaces/IEthFoxVault.sol';
import {Multicall} from '../../../base/Multicall.sol';
import {VaultValidators} from '../../modules/VaultValidators.sol';
import {VaultAdmin} from '../../modules/VaultAdmin.sol';
import {VaultFee} from '../../modules/VaultFee.sol';
import {VaultVersion, IVaultVersion} from '../../modules/VaultVersion.sol';
import {VaultImmutables} from '../../modules/VaultImmutables.sol';
import {VaultState} from '../../modules/VaultState.sol';
import {VaultEnterExit} from '../../modules/VaultEnterExit.sol';
import {VaultEthStaking, IVaultEthStaking} from '../../modules/VaultEthStaking.sol';
import {VaultMev} from '../../modules/VaultMev.sol';
import {VaultBlocklist} from '../../modules/VaultBlocklist.sol';

/**
 * @title EthFoxVault
 * @author StakeWise
 * @notice Custom Ethereum non-ERC20 vault with blocklist, own MEV and without osToken minting.
 */
contract EthFoxVault is
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
  VaultBlocklist,
  Multicall,
  IEthFoxVault
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
   * @param depositDataRegistry The address of the DepositDataRegistry contract
   * @param exitingAssetsClaimDelay The delay after which the assets can be claimed after exiting from staking
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address _keeper,
    address _vaultsRegistry,
    address _validatorsRegistry,
    address sharedMevEscrow,
    address depositDataRegistry,
    uint256 exitingAssetsClaimDelay
  )
    VaultImmutables(_keeper, _vaultsRegistry, _validatorsRegistry)
    VaultValidators(depositDataRegistry)
    VaultEnterExit(exitingAssetsClaimDelay)
    VaultMev(sharedMevEscrow)
  {
    _disableInitializers();
  }

  /// @inheritdoc IEthFoxVault
  function initialize(
    bytes calldata params
  ) external payable virtual override reinitializer(_version) {
    // if admin is already set, it's an upgrade
    if (admin != address(0)) {
      __EthFoxVault_initV2();
      return;
    }
    // initialize deployed vault
    EthFoxVaultInitParams memory initParams = abi.decode(params, (EthFoxVaultInitParams));
    __EthFoxVault_init(initParams);
    emit EthFoxVaultCreated(
      initParams.admin,
      initParams.ownMevEscrow,
      initParams.capacity,
      initParams.feePercent,
      initParams.metadataIpfsHash
    );
  }

  /// @inheritdoc IVaultEthStaking
  function deposit(
    address receiver,
    address referrer
  ) public payable virtual override(IVaultEthStaking, VaultEthStaking) returns (uint256 shares) {
    _checkBlocklist(msg.sender);
    _checkBlocklist(receiver);
    return super.deposit(receiver, referrer);
  }

  /// @inheritdoc IEthFoxVault
  function ejectUser(address user) external override {
    // add user to blocklist
    updateBlocklist(user, true);

    // fetch shares of the user
    uint256 userShares = _balances[user];
    if (userShares == 0) return;

    // send user shares to exit queue
    _enterExitQueue(user, userShares, user);
    emit UserEjected(user, userShares);
  }

  /// @inheritdoc VaultEthStaking
  receive() external payable virtual override {
    _checkBlocklist(msg.sender);
    _deposit(msg.sender, msg.value, address(0));
  }

  /// @inheritdoc VaultVersion
  function vaultId() public pure virtual override(IVaultVersion, VaultVersion) returns (bytes32) {
    return keccak256('EthFoxVault');
  }

  /// @inheritdoc IVaultVersion
  function version() public pure virtual override(IVaultVersion, VaultVersion) returns (uint8) {
    return _version;
  }

  /**
   * @dev Initializes the EthFoxVault contract
   * @param params The decoded parameters for initializing the EthFoxVault contract
   */
  function __EthFoxVault_init(EthFoxVaultInitParams memory params) internal onlyInitializing {
    __VaultAdmin_init(params.admin, params.metadataIpfsHash);
    // fee recipient is initially set to admin address
    __VaultFee_init(params.admin, params.feePercent);
    __VaultState_init(params.capacity);
    __VaultValidators_init();
    __VaultMev_init(params.ownMevEscrow);
    // blocklist manager is initially set to admin address
    __VaultBlocklist_init(params.admin);
    __VaultEthStaking_init();
  }

  /**
   * @dev Initializes the EthFoxVault V2 contract
   */
  function __EthFoxVault_initV2() internal onlyInitializing {
    __VaultState_initV2();
    __VaultValidators_initV2();
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
