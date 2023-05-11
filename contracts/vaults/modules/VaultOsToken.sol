// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {IERC20} from '../../interfaces/IERC20.sol';
import {IOsToken} from '../../interfaces/IOsToken.sol';
import {IOsTokenConfig} from '../../interfaces/IOsTokenConfig.sol';
import {IVaultOsToken} from '../../interfaces/IVaultOsToken.sol';
import {IVaultEnterExit} from '../../interfaces/IVaultEnterExit.sol';
import {IKeeperRewards} from '../../interfaces/IKeeperRewards.sol';
import {IVaultRedeemHook} from '../../interfaces/IVaultRedeemHook.sol';
import {ERC20Upgradeable} from '../../base/ERC20Upgradeable.sol';
import {VaultImmutables} from './VaultImmutables.sol';
import {VaultToken} from './VaultToken.sol';
import {VaultEnterExit} from './VaultEnterExit.sol';

/**
 * @title VaultOsToken
 * @author StakeWise
 * @notice Defines the functionality for minting OsToken
 */
abstract contract VaultOsToken is VaultImmutables, VaultToken, VaultEnterExit, IVaultOsToken {
  uint256 private constant _wad = 1e18;
  uint256 private constant _hfLiqThreshold = 1e18;
  uint256 private constant _maxPercent = 10_000; // @dev 100.00 %

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IOsToken private immutable _osToken;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IOsTokenConfig private immutable _osTokenConfig;

  mapping(address user => OsTokenPosition position) private _positions;

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
    return _getPosition(user).shares;
  }

  /// @inheritdoc IVaultOsToken
  function lockedAssets(address user) external view override returns (uint256 assets) {
    // fetch user position
    uint256 osTokenShares = _getPosition(user).shares;
    if (osTokenShares == 0) return 0;

    // check whether vault assets are up to date
    // if not use static multicall with updateState() to update them
    if (IKeeperRewards(_keeper).isHarvestRequired(address(this))) revert NotHarvested();

    // the locked amount is the minimum between the minted amount (+ extra to maintain current LTV)
    // and the amount of deposited assets
    return
      Math.min(
        convertToAssets(balanceOf[user]),
        Math.mulDiv(
          _osToken.convertToAssets(osTokenShares),
          _maxPercent,
          _osTokenConfig.ltvPercent()
        )
      );
  }

  /// @inheritdoc IVaultOsToken
  function mintOsToken(
    address receiver,
    uint256 assets,
    address referrer
  ) external override returns (uint256 osTokenShares) {
    _checkCollateralized();
    _checkHarvested();
    // mint osToken shares to the receiver
    osTokenShares = _osToken.mintShares(receiver, assets);

    // fetch user position
    OsTokenPosition memory position = _getPosition(msg.sender);

    // add minted shares to the position
    position.shares += SafeCast.toUint128(osTokenShares);

    // calculate and validate position health
    _checkLtv(convertToAssets(balanceOf[msg.sender]), _osToken.convertToAssets(position.shares));

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
    OsTokenPosition memory position = _getPosition(msg.sender);

    // update osToken position
    if (osTokenShares == position.shares) {
      delete _positions[msg.sender];
    } else {
      position.shares -= SafeCast.toUint128(osTokenShares);
      _positions[msg.sender] = position;
    }

    // emit event
    emit OsTokenBurned(msg.sender, assets, osTokenShares);
  }

  /// @inheritdoc IVaultOsToken
  function liquidateOsToken(
    address user,
    uint256 osTokenShares
  ) external override returns (uint256 receivedAssets) {
    _checkHarvested();

    // update osToken state for gas efficiency
    _osToken.updateState();

    // fetch user position
    OsTokenPosition memory position = _getPosition(user);

    // calculate minted assets
    if (position.shares == 0 || osTokenShares > position.shares) revert InvalidShares();

    // fetch deposited assets
    uint256 depositedAssets = convertToAssets(balanceOf[user]);

    // calculate received assets
    receivedAssets = Math.mulDiv(
      _osToken.convertToAssets(osTokenShares),
      _osTokenConfig.liqBonusPercent(),
      _maxPercent
    );
    if (receivedAssets > depositedAssets) revert ReceivedAssetsExceedDeposit();

    // check health factor violation
    if (
      _calcHealthFactor(
        depositedAssets,
        _osToken.convertToAssets(position.shares),
        _osTokenConfig.liqThresholdPercent()
      ) >= _hfLiqThreshold
    ) {
      revert HealthFactorNotViolated();
    }

    // reduce osToken supply
    _osToken.burnShares(msg.sender, osTokenShares);

    // transfer assets to the caller
    _transfer(user, msg.sender, convertToShares(receivedAssets));

    // update osToken position
    if (osTokenShares == position.shares) {
      delete _positions[user];
    } else {
      position.shares -= SafeCast.toUint128(osTokenShares);
      _positions[user] = position;
    }

    // emit event
    emit OsTokenLiquidated(msg.sender, user, osTokenShares, receivedAssets);
  }

  /// @inheritdoc IVaultOsToken
  function redeemOsToken(
    address user,
    uint256 osTokenShares
  ) external override returns (uint256 assets) {
    _checkHarvested();
    if (osTokenShares == 0) revert InvalidShares();

    // update osToken state for gas efficiency
    _osToken.updateState();

    // fetch user position
    OsTokenPosition memory position = _getPosition(user);

    // SLOAD to memory
    uint256 liqThreshold = _osTokenConfig.liqThresholdPercent();

    // calculate health factor and check whether it's less than
    // threshold required to start redeeming user's position
    if (
      _calcHealthFactor(
        convertToAssets(balanceOf[user]),
        _osToken.convertToAssets(position.shares),
        liqThreshold
      ) > _osTokenConfig.redeemStartHealthFactor()
    ) {
      revert InvalidRedeemStartHealthFactor();
    }

    // calculate redeemed assets
    assets = _osToken.convertToAssets(osTokenShares);

    // reduce osToken supply
    _osToken.burnShares(msg.sender, osTokenShares);

    // transfer assets to the caller
    _transfer(user, msg.sender, convertToShares(assets));

    // update osToken position
    if (osTokenShares == position.shares) {
      delete _positions[user];
    } else {
      position.shares -= SafeCast.toUint128(osTokenShares);
      _positions[user] = position;
    }

    // check health factor violation
    if (
      _calcHealthFactor(
        convertToAssets(balanceOf[user]),
        _osToken.convertToAssets(position.shares),
        liqThreshold
      ) > _osTokenConfig.redeemMaxHealthFactor()
    ) {
      revert InvalidRedeemMaxHealthFactor();
    }

    // emit event
    emit OsTokenRedeemed(msg.sender, user, osTokenShares, assets);
  }

  /// @inheritdoc IVaultOsToken
  function redeemWithHook(
    uint256 shares,
    address hook,
    bytes calldata params
  ) external override returns (uint256 assets) {
    _checkHarvested();
    if (shares == 0) revert InvalidShares();
    if (hook == address(0)) revert InvalidRecipient();

    // calculate assets to transfer to the hook
    assets = convertToAssets(shares);

    // reverts in case there are not enough withdrawable assets
    if (assets > withdrawableAssets()) revert InsufficientAssets();

    // transfer assets to the hook
    _transferVaultAssets(hook, assets);

    // execute hook
    if (!IVaultRedeemHook(hook).execute(msg.sender, shares, assets, params)) {
      revert RedeemHookFailed();
    }

    // update state
    balanceOf[hook] -= shares;
    unchecked {
      // cannot underflow because the sum of all shares can't exceed the _totalShares
      _totalShares -= SafeCast.toUint128(shares);
      // cannot underflow because the sum of all assets can't exceed the _totalAssets
      _totalAssets -= SafeCast.toUint128(assets);
    }
    emit Transfer(hook, address(0), shares);
    emit Redeem(msg.sender, hook, hook, assets, shares);

    _checkPosition(hook);
  }

  /// @inheritdoc IVaultEnterExit
  function redeem(
    uint256 shares,
    address receiver,
    address owner
  ) public virtual override(IVaultEnterExit, VaultEnterExit) returns (uint256 assets) {
    assets = super.redeem(shares, receiver, owner);
    _checkPosition(owner);
  }

  /// @inheritdoc IVaultEnterExit
  function enterExitQueue(
    uint256 shares,
    address receiver,
    address owner
  ) public virtual override(IVaultEnterExit, VaultEnterExit) returns (uint256 positionCounter) {
    positionCounter = super.enterExitQueue(shares, receiver, owner);
    _checkPosition(owner);
  }

  /// @inheritdoc IERC20
  function transfer(
    address to,
    uint256 amount
  ) public virtual override(IERC20, ERC20Upgradeable) returns (bool) {
    bool success = super.transfer(to, amount);
    _checkPosition(msg.sender);
    return success;
  }

  /// @inheritdoc IERC20
  function transferFrom(
    address from,
    address to,
    uint256 amount
  ) public virtual override(IERC20, ERC20Upgradeable) returns (bool) {
    bool success = super.transferFrom(from, to, amount);
    _checkPosition(from);
    return success;
  }

  /**
   * @dev Internal function for retrieving the user position
   * @param user The address of the user
   * @return position The user synced position
   */
  function _getPosition(address user) private view returns (OsTokenPosition memory position) {
    position = _positions[user];

    // fetch current cumulative fee per share
    uint256 cumulativeFeePerShare = _osToken.cumulativeFeePerShare();

    // check whether fee is already up to date
    if (cumulativeFeePerShare == position.cumulativeFeePerShare) return position;

    // check whether user minted anything
    if (position.shares == 0) {
      // nothing is minted, checkpoint current cumulativeFeePerShare
      position.cumulativeFeePerShare = SafeCast.toUint128(cumulativeFeePerShare);
      return position;
    }

    // update position
    position.cumulativeFeePerShare = SafeCast.toUint128(cumulativeFeePerShare);

    // add treasury fee to the position
    position.shares += SafeCast.toUint128(
      Math.mulDiv(cumulativeFeePerShare - position.cumulativeFeePerShare, position.shares, _wad)
    );
  }

  /**
   * @notice Internal function for checking position validity
   * @param user The address of the user
   */
  function _checkPosition(address user) private view {
    OsTokenPosition memory position = _getPosition(user);
    if (position.shares == 0) return;

    // check whether vault assets are up to date
    if (IKeeperRewards(_keeper).isHarvestRequired(address(this))) revert NotHarvested();

    // calculate and validate position health
    _checkLtv(convertToAssets(balanceOf[user]), _osToken.convertToAssets(position.shares));
  }

  /**
   * @notice Internal function for checking the health of the position. Reverts if it is lower than threshold.
   * @param depositedAssets The number of deposited assets
   * @param mintedAssets The number of minted assets
   */
  function _checkLtv(uint256 depositedAssets, uint256 mintedAssets) private view {
    if (mintedAssets == 0) return;
    if (Math.mulDiv(depositedAssets, _osTokenConfig.ltvPercent(), _maxPercent) < mintedAssets) {
      revert LowLtv();
    }
  }

  function _calcHealthFactor(
    uint256 depositedAssets,
    uint256 mintedAssets,
    uint256 liqThresholdPercent
  ) private pure returns (uint256) {
    if (mintedAssets == 0) return type(uint256).max;
    return Math.mulDiv(depositedAssets * _wad, liqThresholdPercent, mintedAssets * _maxPercent);
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
