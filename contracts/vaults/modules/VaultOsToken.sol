// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {IERC20} from '../../interfaces/IERC20.sol';
import {IOsToken} from '../../interfaces/IOsToken.sol';
import {IOsTokenConfig} from '../../interfaces/IOsTokenConfig.sol';
import {IVaultOsToken} from '../../interfaces/IVaultOsToken.sol';
import {IVaultEnterExit} from '../../interfaces/IVaultEnterExit.sol';
import {Errors} from '../../libraries/Errors.sol';
import {VaultImmutables} from './VaultImmutables.sol';
import {VaultEnterExit} from './VaultEnterExit.sol';
import {VaultState} from './VaultState.sol';

/**
 * @title VaultOsToken
 * @author StakeWise
 * @notice Defines the functionality for minting OsToken
 */
abstract contract VaultOsToken is VaultImmutables, VaultState, VaultEnterExit, IVaultOsToken {
  uint256 private constant _wad = 1e18;
  uint256 private constant _hfLiqThreshold = 1e18;
  uint256 private constant _maxPercent = 10_000; // @dev 100.00 %

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IOsToken private immutable _osToken;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IOsTokenConfig private immutable _osTokenConfig;

  mapping(address => OsTokenPosition) private _positions;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param osToken The address of the OsToken contract
   * @param osTokenConfig The address of the OsTokenConfig contract
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(address osToken, address osTokenConfig) {
    _osToken = IOsToken(osToken);
    _osTokenConfig = IOsTokenConfig(osTokenConfig);
  }

  /// @inheritdoc IVaultOsToken
  function osTokenPositions(address user) external view override returns (uint128 shares) {
    OsTokenPosition memory position = _positions[user];
    if (position.shares > 0) _syncPositionFee(position);
    return position.shares;
  }

  /// @inheritdoc IVaultOsToken
  function mintOsToken(
    address receiver,
    uint256 osTokenShares,
    address referrer
  ) external override returns (uint256 assets) {
    _checkCollateralized();
    _checkHarvested();

    // mint osToken shares to the receiver
    assets = _osToken.mintShares(receiver, osTokenShares);

    // fetch user position
    OsTokenPosition memory position = _positions[msg.sender];
    if (position.shares > 0) {
      _syncPositionFee(position);
    } else {
      position.cumulativeFeePerShare = SafeCast.toUint128(_osToken.cumulativeFeePerShare());
    }

    // add minted shares to the position
    position.shares += SafeCast.toUint128(osTokenShares);

    // calculate and validate LTV
    if (
      Math.mulDiv(
        convertToAssets(_balances[msg.sender]),
        _osTokenConfig.ltvPercent(),
        _maxPercent
      ) < _osToken.convertToAssets(position.shares)
    ) {
      revert Errors.LowLtv();
    }

    // update state
    _positions[msg.sender] = position;

    // emit event
    emit OsTokenMinted(msg.sender, receiver, assets, osTokenShares, referrer);
  }

  /// @inheritdoc IVaultOsToken
  function burnOsToken(uint128 osTokenShares) external override returns (uint256 assets) {
    // burn osToken shares
    assets = _osToken.burnShares(msg.sender, osTokenShares);

    // fetch user position
    OsTokenPosition memory position = _positions[msg.sender];
    if (position.shares == 0) revert Errors.InvalidPosition();
    _syncPositionFee(position);

    // update osToken position
    position.shares -= SafeCast.toUint128(osTokenShares);
    _positions[msg.sender] = position;

    // emit event
    emit OsTokenBurned(msg.sender, assets, osTokenShares);
  }

  /// @inheritdoc IVaultOsToken
  function liquidateOsToken(
    uint256 osTokenShares,
    address owner,
    address receiver
  ) external override returns (uint256 receivedAssets) {
    receivedAssets = _redeemOsToken(owner, receiver, osTokenShares, true);
    emit OsTokenLiquidated(msg.sender, owner, receiver, osTokenShares, receivedAssets);
  }

  /// @inheritdoc IVaultOsToken
  function redeemOsToken(
    uint256 osTokenShares,
    address owner,
    address receiver
  ) external override returns (uint256 receivedAssets) {
    receivedAssets = _redeemOsToken(owner, receiver, osTokenShares, false);
    emit OsTokenRedeemed(msg.sender, owner, receiver, osTokenShares, receivedAssets);
  }

  /// @inheritdoc IVaultEnterExit
  function redeem(
    uint256 shares,
    address receiver
  ) public virtual override(IVaultEnterExit, VaultEnterExit) returns (uint256 assets) {
    assets = super.redeem(shares, receiver);
    _checkOsTokenPosition(msg.sender);
  }

  /// @inheritdoc IVaultEnterExit
  function enterExitQueue(
    uint256 shares,
    address receiver
  ) public virtual override(IVaultEnterExit, VaultEnterExit) returns (uint256 positionTicket) {
    positionTicket = super.enterExitQueue(shares, receiver);
    _checkOsTokenPosition(msg.sender);
  }

  /**
   * @dev Internal function for redeeming and liquidating osToken shares
   * @param owner The minter of the osToken shares
   * @param receiver The receiver of the assets
   * @param osTokenShares The amount of osToken shares to redeem or liquidate
   * @param isLiquidation Whether the liquidation or redemption is being performed
   * @return receivedAssets The amount of assets received
   */
  function _redeemOsToken(
    address owner,
    address receiver,
    uint256 osTokenShares,
    bool isLiquidation
  ) private returns (uint256 receivedAssets) {
    if (receiver == address(0)) revert Errors.ZeroAddress();
    _checkHarvested();

    // update osToken state for gas efficiency
    _osToken.updateState();

    // fetch user position
    OsTokenPosition memory position = _positions[owner];
    if (position.shares == 0) revert Errors.InvalidPosition();
    _syncPositionFee(position);

    // SLOAD to memory
    (
      uint256 redeemFromLtvPercent,
      uint256 redeemToLtvPercent,
      uint256 liqThresholdPercent,
      uint256 liqBonusPercent,

    ) = _osTokenConfig.getConfig();

    // calculate received assets
    if (isLiquidation) {
      receivedAssets = Math.mulDiv(
        _osToken.convertToAssets(osTokenShares),
        liqBonusPercent,
        _maxPercent
      );
    } else {
      receivedAssets = _osToken.convertToAssets(osTokenShares);
    }

    {
      // check whether received assets are valid
      uint256 depositedAssets = convertToAssets(_balances[owner]);
      if (receivedAssets > depositedAssets || receivedAssets > withdrawableAssets()) {
        revert Errors.InvalidReceivedAssets();
      }

      uint256 mintedAssets = _osToken.convertToAssets(position.shares);
      if (isLiquidation) {
        // check health factor violation in case of liquidation
        if (
          Math.mulDiv(depositedAssets * _wad, liqThresholdPercent, mintedAssets * _maxPercent) >=
          _hfLiqThreshold
        ) {
          revert Errors.InvalidHealthFactor();
        }
      } else if (
        // check ltv violation in case of redemption
        Math.mulDiv(depositedAssets, redeemFromLtvPercent, _maxPercent) > mintedAssets
      ) {
        revert Errors.InvalidLtv();
      }
    }

    // reduce osToken supply
    _osToken.burnShares(msg.sender, osTokenShares);

    // update osToken position
    position.shares -= SafeCast.toUint128(osTokenShares);
    _positions[owner] = position;

    uint256 sharesToBurn = convertToShares(receivedAssets);

    // update total assets
    unchecked {
      _totalAssets -= SafeCast.toUint128(receivedAssets);
    }

    // burn owner shares
    _burnShares(owner, sharesToBurn);

    // check ltv violation in case of redemption
    if (
      !isLiquidation &&
      Math.mulDiv(convertToAssets(_balances[owner]), redeemToLtvPercent, _maxPercent) >
      _osToken.convertToAssets(position.shares)
    ) {
      revert Errors.RedemptionExceeded();
    }

    // transfer assets to the receiver
    _transferVaultAssets(receiver, receivedAssets);
  }

  /**
   * @dev Internal function for syncing the osToken fee
   * @param position The position to sync the fee for
   */
  function _syncPositionFee(OsTokenPosition memory position) private view {
    // fetch current cumulative fee per share
    uint256 cumulativeFeePerShare = _osToken.cumulativeFeePerShare();

    // check whether fee is already up to date
    if (cumulativeFeePerShare == position.cumulativeFeePerShare) return;

    // add treasury fee to the position
    position.shares = SafeCast.toUint128(
      Math.mulDiv(position.shares, cumulativeFeePerShare, position.cumulativeFeePerShare)
    );
    position.cumulativeFeePerShare = SafeCast.toUint128(cumulativeFeePerShare);
  }

  /**
   * @notice Internal function for checking position validity. Reverts if it is invalid.
   * @param user The address of the user
   */
  function _checkOsTokenPosition(address user) internal view {
    // fetch user position
    OsTokenPosition memory position = _positions[user];
    if (position.shares == 0) return;

    // check whether vault assets are up to date
    _checkHarvested();

    // sync fee
    _syncPositionFee(position);

    // calculate and validate position LTV
    if (
      Math.mulDiv(convertToAssets(_balances[user]), _osTokenConfig.ltvPercent(), _maxPercent) <
      _osToken.convertToAssets(position.shares)
    ) {
      revert Errors.LowLtv();
    }
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
