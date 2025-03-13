// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IGnoVault} from '../../interfaces/IGnoVault.sol';
import {IGnoVaultFactory} from '../../interfaces/IGnoVaultFactory.sol';
import {Errors} from '../../libraries/Errors.sol';
import {Multicall} from '../../base/Multicall.sol';
import {VaultValidators} from '../modules/VaultValidators.sol';
import {VaultAdmin} from '../modules/VaultAdmin.sol';
import {VaultFee} from '../modules/VaultFee.sol';
import {VaultVersion, IVaultVersion} from '../modules/VaultVersion.sol';
import {VaultImmutables} from '../modules/VaultImmutables.sol';
import {VaultState} from '../modules/VaultState.sol';
import {VaultEnterExit, IVaultEnterExit} from '../modules/VaultEnterExit.sol';
import {VaultOsToken} from '../modules/VaultOsToken.sol';
import {VaultGnoStaking} from '../modules/VaultGnoStaking.sol';
import {VaultMev} from '../modules/VaultMev.sol';

/**
 * @title GnoVault
 * @author StakeWise
 * @notice Defines the Gnosis staking Vault
 */
contract GnoVault is
  VaultImmutables,
  Initializable,
  VaultAdmin,
  VaultVersion,
  VaultFee,
  VaultState,
  VaultValidators,
  VaultEnterExit,
  VaultOsToken,
  VaultMev,
  VaultGnoStaking,
  Multicall,
  IGnoVault
{
  uint8 private constant _version = 3;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param _keeper The address of the Keeper contract
   * @param _vaultsRegistry The address of the VaultsRegistry contract
   * @param _validatorsRegistry The contract address used for registering validators in beacon chain
   * @param _validatorsWithdrawals The contract address used for withdrawing validators in beacon chain
   * @param _validatorsConsolidations The contract address used for consolidating validators in beacon chain
   * @param _consolidationsChecker The contract address used for checking consolidations
   * @param osTokenVaultController The address of the OsTokenVaultController contract
   * @param osTokenConfig The address of the OsTokenConfig contract
   * @param osTokenVaultEscrow The address of the OsTokenVaultEscrow contract
   * @param sharedMevEscrow The address of the shared MEV escrow
   * @param gnoToken The address of the GNO token
   * @param gnosisDaiDistributor The address of the GnosisDaiDistributor contract
   * @param exitingAssetsClaimDelay The delay after which the assets can be claimed after exiting from staking
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address _keeper,
    address _vaultsRegistry,
    address _validatorsRegistry,
    address _validatorsWithdrawals,
    address _validatorsConsolidations,
    address _consolidationsChecker,
    address osTokenVaultController,
    address osTokenConfig,
    address osTokenVaultEscrow,
    address sharedMevEscrow,
    address gnoToken,
    address gnosisDaiDistributor,
    uint256 exitingAssetsClaimDelay
  )
    VaultImmutables(_keeper, _vaultsRegistry)
    VaultValidators(
      _validatorsRegistry,
      _validatorsWithdrawals,
      _validatorsConsolidations,
      _consolidationsChecker
    )
    VaultEnterExit(exitingAssetsClaimDelay)
    VaultOsToken(osTokenVaultController, osTokenConfig, osTokenVaultEscrow)
    VaultMev(sharedMevEscrow)
    VaultGnoStaking(gnoToken, gnosisDaiDistributor)
  {
    _disableInitializers();
  }

  /// @inheritdoc IGnoVault
  function initialize(bytes calldata params) external virtual override reinitializer(_version) {
    // if admin is already set, it's an upgrade from version 2 to 3
    if (admin != address(0)) {
      __GnoVault_upgrade();
      return;
    }

    // initialize deployed vault
    __GnoVault_init(
      IGnoVaultFactory(msg.sender).vaultAdmin(),
      IGnoVaultFactory(msg.sender).ownMevEscrow(),
      abi.decode(params, (GnoVaultInitParams))
    );
  }

  /// @inheritdoc IVaultEnterExit
  function enterExitQueue(
    uint256 shares,
    address receiver
  )
    public
    virtual
    override(IVaultEnterExit, VaultEnterExit, VaultOsToken)
    returns (uint256 positionTicket)
  {
    return super.enterExitQueue(shares, receiver);
  }

  /// @inheritdoc VaultVersion
  function vaultId() public pure virtual override(IVaultVersion, VaultVersion) returns (bytes32) {
    return keccak256('GnoVault');
  }

  /// @inheritdoc IVaultVersion
  function version() public pure virtual override(IVaultVersion, VaultVersion) returns (uint8) {
    return _version;
  }

  /// @inheritdoc VaultState
  function _processTotalAssetsDelta(
    int256 assetsDelta
  ) internal virtual override(VaultState, VaultGnoStaking) {
    super._processTotalAssetsDelta(assetsDelta);
  }

  /// @inheritdoc VaultValidators
  function _checkCanWithdrawValidators(
    bytes calldata validators,
    bytes calldata validatorsManagerSignature
  ) internal override {
    if (
      !_isValidatorsManager(validators, validatorsManagerSignature) &&
      msg.sender != _osTokenConfig.redeemer()
    ) {
      revert Errors.AccessDenied();
    }
  }

  /// @inheritdoc VaultValidators
  function _withdrawValidator(
    bytes calldata validator
  )
    internal
    override(VaultValidators, VaultGnoStaking)
    returns (bytes calldata publicKey, uint256 withdrawnAmount, uint256 feePaid)
  {
    return super._withdrawValidator(validator);
  }

  /**
   * @dev Upgrades the GnoVault contract
   */
  function __GnoVault_upgrade() internal {
    __VaultState_upgrade();
    __VaultValidators_upgrade();
    __VaultGnoStaking_upgrade();
  }

  /**
   * @dev Initializes the GnoVault contract
   * @param admin The address of the admin of the Vault
   * @param ownMevEscrow The address of the MEV escrow owned by the Vault. Zero address if shared MEV escrow is used.
   * @param params The decoded parameters for initializing the GnoVault contract
   */
  function __GnoVault_init(
    address admin,
    address ownMevEscrow,
    GnoVaultInitParams memory params
  ) internal onlyInitializing {
    __VaultAdmin_init(admin, params.metadataIpfsHash);
    // fee recipient is initially set to admin address
    __VaultFee_init(admin, params.feePercent);
    __VaultState_init(params.capacity);
    __VaultValidators_init();
    __VaultMev_init(ownMevEscrow);
    __VaultGnoStaking_init();
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
