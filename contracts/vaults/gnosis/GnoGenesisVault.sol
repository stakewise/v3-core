// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {IGnoValidatorsRegistry} from '../../interfaces/IGnoValidatorsRegistry.sol';
import {IVaultVersion} from '../../interfaces/IVaultVersion.sol';
import {IGnoPoolEscrow} from '../../interfaces/IGnoPoolEscrow.sol';
import {IGnoGenesisVault} from '../../interfaces/IGnoGenesisVault.sol';
import {IRewardGnoToken} from '../../interfaces/IRewardGnoToken.sol';
import {Errors} from '../../libraries/Errors.sol';
import {VaultGnoStaking} from '../modules/VaultGnoStaking.sol';
import {VaultState, IVaultState} from '../modules/VaultState.sol';
import {GnoVault, IGnoVault} from './GnoVault.sol';

/**
 * @title GnoGenesisVault
 * @author StakeWise
 * @notice Defines the Genesis Vault for Gnosis staking migrated from StakeWise Legacy
 */
contract GnoGenesisVault is Initializable, GnoVault, IGnoGenesisVault {
  // slither-disable-next-line shadowing-state
  uint8 private constant _version = 4;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IGnoPoolEscrow private immutable _poolEscrow;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IRewardGnoToken private immutable _rewardGnoToken;

  error InvalidInitialHarvest();

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
   * @param poolEscrow The address of the pool escrow from StakeWise Legacy
   * @param rewardGnoToken The address of the rGNO token from StakeWise Legacy
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
    address poolEscrow,
    address rewardGnoToken,
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
  {
    _poolEscrow = IGnoPoolEscrow(poolEscrow);
    _rewardGnoToken = IRewardGnoToken(rewardGnoToken);
  }

  /// @inheritdoc IGnoVault
  function initialize(
    bytes calldata
  ) external virtual override(IGnoVault, GnoVault) reinitializer(_version) {
    if (admin == address(0)) {
      revert Errors.UpgradeFailed();
    }
    __GnoVault_upgrade();
  }

  /// @inheritdoc IVaultVersion
  function vaultId() public pure virtual override(IVaultVersion, GnoVault) returns (bytes32) {
    return keccak256('GnoGenesisVault');
  }

  /// @inheritdoc IVaultVersion
  function version() public pure virtual override(IVaultVersion, GnoVault) returns (uint8) {
    return _version;
  }

  /// @inheritdoc IGnoGenesisVault
  function migrate(address receiver, uint256 assets) external override returns (uint256 shares) {
    if (msg.sender != address(_rewardGnoToken) || _poolEscrow.owner() != address(this)) {
      revert Errors.AccessDenied();
    }

    _checkCollateralized();
    _checkHarvested();
    if (receiver == address(0)) revert Errors.ZeroAddress();
    if (assets == 0) revert Errors.InvalidAssets();

    // calculate amount of shares to mint
    shares = convertToShares(assets);

    // update state
    _totalAssets += SafeCast.toUint128(assets);
    _mintShares(receiver, shares);

    // mint max possible OsToken shares
    uint256 mintOsTokenShares = Math.min(
      _calcMaxMintOsTokenShares(receiver),
      _calcMaxOsTokenShares(assets)
    );
    if (mintOsTokenShares > 0) {
      _mintOsToken(receiver, receiver, mintOsTokenShares, address(0));
    }

    emit Migrated(receiver, assets, shares);
  }

  /**
   * @dev Internal function for calculating the maximum amount of osToken shares that can be minted
   *      based on the current user balance
   * @param user The address of the user
   * @return The maximum amount of osToken shares that can be minted
   */
  function _calcMaxMintOsTokenShares(address user) private view returns (uint256) {
    uint256 userAssets = convertToAssets(_balances[user]);
    if (userAssets == 0) return 0;

    // fetch user position
    uint256 mintedShares = osTokenPositions(user);

    // calculate max osToken shares that user can mint based on its current staked balance and osToken position
    uint256 userMaxOsTokenShares = _calcMaxOsTokenShares(userAssets);
    unchecked {
      // cannot underflow because mintedShares < userMaxOsTokenShares
      return mintedShares < userMaxOsTokenShares ? userMaxOsTokenShares - mintedShares : 0;
    }
  }

  /// @inheritdoc VaultState
  function _vaultAssets()
    internal
    view
    virtual
    override(VaultState, VaultGnoStaking)
    returns (uint256)
  {
    return
      super._vaultAssets() +
      _gnoToken.balanceOf(address(_poolEscrow)) +
      IGnoValidatorsRegistry(_validatorsRegistry).withdrawableAmount(address(_poolEscrow));
  }

  /// @inheritdoc VaultGnoStaking
  function _pullWithdrawals() internal override {
    super._pullWithdrawals();
    IGnoValidatorsRegistry(_validatorsRegistry).claimWithdrawal(address(_poolEscrow));
    uint256 escrowAssets = _gnoToken.balanceOf(address(_poolEscrow));
    if (escrowAssets != 0) {
      _poolEscrow.withdrawTokens(address(_gnoToken), address(this), escrowAssets);
    }
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
