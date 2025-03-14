// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IGnoBlocklistVault} from '../../interfaces/IGnoBlocklistVault.sol';
import {IGnoVaultFactory} from '../../interfaces/IGnoVaultFactory.sol';
import {VaultOsToken, IVaultOsToken} from '../modules/VaultOsToken.sol';
import {VaultGnoStaking, IVaultGnoStaking} from '../modules/VaultGnoStaking.sol';
import {VaultBlocklist} from '../modules/VaultBlocklist.sol';
import {VaultVersion, IVaultVersion} from '../modules/VaultVersion.sol';
import {GnoVault, IGnoVault} from './GnoVault.sol';

/**
 * @title GnoBlocklistVault
 * @author StakeWise
 * @notice Defines the Gnosis staking Vault with blocking addresses functionality
 */
contract GnoBlocklistVault is Initializable, GnoVault, VaultBlocklist, IGnoBlocklistVault {
  // slither-disable-next-line shadowing-state
  uint8 private constant _version = 3;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param keeper The address of the Keeper contract
   * @param vaultsRegistry The address of the VaultsRegistry contract
   * @param validatorsRegistry The contract address used for registering validators in beacon chain
   * @param validatorsWithdrawals The contract address used for withdrawing validators in beacon chain
   * @param validatorsConsolidations The contract address used for consolidating validators in beacon chain
   * @param consolidationsChecker The contract address used for checking consolidations
   * @param osTokenVaultController The address of the OsTokenVaultController contract
   * @param osTokenConfig The address of the OsTokenConfig contract
   * @param osTokenVaultEscrow The address of the OsTokenVaultEscrow contract
   * @param sharedMevEscrow The address of the shared MEV escrow
   * @param depositDataRegistry The address of the DepositDataRegistry contract
   * @param gnoToken The address of the GNO token
   * @param gnoDaiDistributor The address of the GnoDaiDistributor contract
   * @param exitingAssetsClaimDelay The delay after which the assets can be claimed after exiting from staking
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address keeper,
    address vaultsRegistry,
    address validatorsRegistry,
    address validatorsWithdrawals,
    address validatorsConsolidations,
    address consolidationsChecker,
    address osTokenVaultController,
    address osTokenConfig,
    address osTokenVaultEscrow,
    address sharedMevEscrow,
    address depositDataRegistry,
    address gnoToken,
    address gnoDaiDistributor,
    uint256 exitingAssetsClaimDelay
  )
    GnoVault(
      keeper,
      vaultsRegistry,
      validatorsRegistry,
      validatorsWithdrawals,
      validatorsConsolidations,
      consolidationsChecker,
      osTokenVaultController,
      osTokenConfig,
      osTokenVaultEscrow,
      sharedMevEscrow,
      depositDataRegistry,
      gnoToken,
      gnoDaiDistributor,
      exitingAssetsClaimDelay
    )
  {}

  /// @inheritdoc IGnoVault
  function initialize(
    bytes calldata params
  ) external virtual override(IGnoVault, GnoVault) reinitializer(_version) {
    // if admin is already set, it's an upgrade from version 2 to 3
    if (admin != address(0)) {
      __GnoVault_upgrade();
      return;
    }

    // initialize deployed vault
    address _admin = IGnoVaultFactory(msg.sender).vaultAdmin();
    __GnoVault_init(
      _admin,
      IGnoVaultFactory(msg.sender).ownMevEscrow(),
      abi.decode(params, (GnoVaultInitParams))
    );
    // blocklist manager is initially set to admin address
    __VaultBlocklist_init(_admin);
  }

  /// @inheritdoc IVaultGnoStaking
  function deposit(
    uint256 assets,
    address receiver,
    address referrer
  ) public virtual override(IVaultGnoStaking, VaultGnoStaking) returns (uint256 shares) {
    _checkBlocklist(msg.sender);
    _checkBlocklist(receiver);
    return super.deposit(assets, receiver, referrer);
  }

  /// @inheritdoc IVaultOsToken
  function mintOsToken(
    address receiver,
    uint256 osTokenShares,
    address referrer
  ) public virtual override(IVaultOsToken, VaultOsToken) returns (uint256 assets) {
    _checkBlocklist(msg.sender);
    return super.mintOsToken(receiver, osTokenShares, referrer);
  }

  /// @inheritdoc IVaultVersion
  function vaultId() public pure virtual override(IVaultVersion, GnoVault) returns (bytes32) {
    return keccak256('GnoBlocklistVault');
  }

  /// @inheritdoc IVaultVersion
  function version() public pure virtual override(IVaultVersion, GnoVault) returns (uint8) {
    return _version;
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
