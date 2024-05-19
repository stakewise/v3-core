// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Ownable2Step, Ownable} from '@openzeppelin/contracts/access/Ownable2Step.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {Errors} from '../libraries/Errors.sol';
import {IVaultsRegistry} from '../interfaces/IVaultsRegistry.sol';
import {IOsToken} from '../interfaces/IOsToken.sol';
import {IVaultVersion} from '../interfaces/IVaultVersion.sol';
import {IOsTokenVaultController} from '../interfaces/IOsTokenVaultController.sol';

/**
 * @title OsTokenVaultController
 * @author StakeWise
 * @notice Over-collateralized staked token controller
 */
contract OsTokenVaultController is Ownable2Step, IOsTokenVaultController {
  uint256 private constant _wad = 1e18;
  uint256 private constant _maxFeePercent = 10_000; // @dev 100.00 %

  address private immutable _registry;
  address private immutable _osToken;

  /// @inheritdoc IOsTokenVaultController
  address public override keeper;

  /// @inheritdoc IOsTokenVaultController
  uint256 public override capacity;

  /// @inheritdoc IOsTokenVaultController
  uint256 public override avgRewardPerSecond;

  /// @inheritdoc IOsTokenVaultController
  address public override treasury;

  /// @inheritdoc IOsTokenVaultController
  uint64 public override feePercent;

  uint192 private _cumulativeFeePerShare = uint192(_wad);
  uint64 private _lastUpdateTimestamp;

  uint128 private _totalShares;
  uint128 private _totalAssets;

  /**
   * @dev Constructor
   * @param _keeper The address of the Keeper contract
   * @param registry The address of the VaultsRegistry contract
   * @param osToken The address of the OsToken contract
   * @param _treasury The address of the DAO treasury
   * @param _owner The address of the owner of the contract
   * @param _feePercent The fee percent applied on the rewards
   * @param _capacity The amount after which the osToken stops accepting deposits
   */
  constructor(
    address _keeper,
    address registry,
    address osToken,
    address _treasury,
    address _owner,
    uint16 _feePercent,
    uint256 _capacity
  ) Ownable(msg.sender) {
    if (_owner == address(0)) revert Errors.ZeroAddress();
    keeper = _keeper;
    _registry = registry;
    _osToken = osToken;
    _lastUpdateTimestamp = uint64(block.timestamp);

    setCapacity(_capacity);
    setTreasury(_treasury);
    setFeePercent(_feePercent);
    _transferOwnership(_owner);
  }

  /// @inheritdoc IOsTokenVaultController
  function totalShares() external view override returns (uint256) {
    return _totalShares;
  }

  /// @inheritdoc IOsTokenVaultController
  function totalAssets() public view override returns (uint256) {
    uint256 profitAccrued = _unclaimedAssets();
    if (profitAccrued == 0) return _totalAssets;

    uint256 treasuryAssets = Math.mulDiv(profitAccrued, feePercent, _maxFeePercent);
    return _totalAssets + profitAccrued - treasuryAssets;
  }

  /// @inheritdoc IOsTokenVaultController
  function convertToShares(uint256 assets) public view override returns (uint256 shares) {
    return _convertToShares(assets, _totalShares, totalAssets(), Math.Rounding.Floor);
  }

  /// @inheritdoc IOsTokenVaultController
  function convertToAssets(uint256 shares) public view override returns (uint256 assets) {
    return _convertToAssets(shares, _totalShares, totalAssets(), Math.Rounding.Floor);
  }

  /// @inheritdoc IOsTokenVaultController
  function mintShares(address receiver, uint256 shares) external override returns (uint256 assets) {
    if (
      !IVaultsRegistry(_registry).vaults(msg.sender) ||
      !IVaultsRegistry(_registry).vaultImpls(IVaultVersion(msg.sender).implementation())
    ) {
      revert Errors.AccessDenied();
    }
    if (receiver == address(0)) revert Errors.ZeroAddress();
    if (shares == 0) revert Errors.InvalidShares();

    // pull accumulated rewards
    updateState();

    // calculate amount of assets to mint
    assets = convertToAssets(shares);

    uint256 totalAssetsAfter = _totalAssets + assets;
    if (totalAssetsAfter > capacity) revert Errors.CapacityExceeded();

    // update counters
    _totalShares += SafeCast.toUint128(shares);
    _totalAssets = SafeCast.toUint128(totalAssetsAfter);

    // mint shares
    IOsToken(_osToken).mint(receiver, shares);
    emit Mint(msg.sender, receiver, assets, shares);
  }

  /// @inheritdoc IOsTokenVaultController
  function burnShares(address owner, uint256 shares) external override returns (uint256 assets) {
    if (!IVaultsRegistry(_registry).vaults(msg.sender)) revert Errors.AccessDenied();
    if (shares == 0) revert Errors.InvalidShares();

    // pull accumulated rewards
    updateState();

    // calculate amount of assets to burn
    assets = convertToAssets(shares);

    // burn shares
    IOsToken(_osToken).burn(owner, shares);

    // update counters
    unchecked {
      // cannot underflow because the sum of all shares can't exceed the _totalShares
      _totalShares -= SafeCast.toUint128(shares);
      // cannot underflow because the sum of all assets can't exceed the _totalAssets
      _totalAssets -= SafeCast.toUint128(assets);
    }
    emit Burn(msg.sender, owner, assets, shares);
  }

  /// @inheritdoc IOsTokenVaultController
  function setCapacity(uint256 _capacity) public override onlyOwner {
    // update os token capacity
    capacity = _capacity;
    emit CapacityUpdated(_capacity);
  }

  /// @inheritdoc IOsTokenVaultController
  function setTreasury(address _treasury) public override onlyOwner {
    if (_treasury == address(0)) revert Errors.ZeroAddress();

    // update DAO treasury address
    treasury = _treasury;
    emit TreasuryUpdated(_treasury);
  }

  /// @inheritdoc IOsTokenVaultController
  function setFeePercent(uint16 _feePercent) public override onlyOwner {
    if (_feePercent > _maxFeePercent) revert Errors.InvalidFeePercent();
    // pull reward with the current fee percent
    updateState();

    // update fee percent
    feePercent = _feePercent;
    emit FeePercentUpdated(_feePercent);
  }

  /// @inheritdoc IOsTokenVaultController
  function setAvgRewardPerSecond(uint256 _avgRewardPerSecond) external override {
    if (msg.sender != keeper) revert Errors.AccessDenied();

    updateState();
    avgRewardPerSecond = _avgRewardPerSecond;
    emit AvgRewardPerSecondUpdated(_avgRewardPerSecond);
  }

  /// @inheritdoc IOsTokenVaultController
  function setKeeper(address _keeper) external override onlyOwner {
    if (_keeper == address(0)) revert Errors.ZeroAddress();

    keeper = _keeper;
    emit KeeperUpdated(_keeper);
  }

  /// @inheritdoc IOsTokenVaultController
  function cumulativeFeePerShare() external view override returns (uint256) {
    // SLOAD to memory
    uint256 currCumulativeFeePerShare = _cumulativeFeePerShare;

    // calculate rewards
    uint256 profitAccrued = _unclaimedAssets();
    if (profitAccrued == 0) return currCumulativeFeePerShare;

    // calculate treasury assets
    uint256 treasuryAssets = Math.mulDiv(profitAccrued, feePercent, _maxFeePercent);
    if (treasuryAssets == 0) return currCumulativeFeePerShare;

    // SLOAD to memory
    uint256 totalShares_ = _totalShares;

    // calculate treasury shares
    uint256 treasuryShares;
    unchecked {
      treasuryShares = _convertToShares(
        treasuryAssets,
        totalShares_,
        // cannot underflow because profitAccrued >= treasuryAssets
        _totalAssets + profitAccrued - treasuryAssets,
        Math.Rounding.Floor
      );
    }

    return currCumulativeFeePerShare + Math.mulDiv(treasuryShares, _wad, totalShares_);
  }

  /// @inheritdoc IOsTokenVaultController
  function updateState() public override {
    // calculate rewards
    uint256 profitAccrued = _unclaimedAssets();

    // check whether any profit accrued
    if (profitAccrued == 0) {
      if (_lastUpdateTimestamp != block.timestamp) {
        _lastUpdateTimestamp = uint64(block.timestamp);
      }
      return;
    }

    // calculate treasury assets
    uint256 newTotalAssets = _totalAssets + profitAccrued;
    uint256 treasuryAssets = Math.mulDiv(profitAccrued, feePercent, _maxFeePercent);
    if (treasuryAssets == 0) {
      // no treasury assets
      _lastUpdateTimestamp = uint64(block.timestamp);
      _totalAssets = SafeCast.toUint128(newTotalAssets);
      return;
    }

    // SLOAD to memory
    uint256 totalShares_ = _totalShares;

    // calculate treasury shares
    uint256 treasuryShares;
    unchecked {
      treasuryShares = _convertToShares(
        treasuryAssets,
        totalShares_,
        // cannot underflow because newTotalAssets >= treasuryAssets
        newTotalAssets - treasuryAssets,
        Math.Rounding.Floor
      );
    }

    // SLOAD to memory
    address _treasury = treasury;

    // mint shares to the fee recipient
    IOsToken(_osToken).mint(_treasury, treasuryShares);

    // update state
    _cumulativeFeePerShare += SafeCast.toUint192(Math.mulDiv(treasuryShares, _wad, totalShares_));
    _lastUpdateTimestamp = uint64(block.timestamp);
    _totalAssets = SafeCast.toUint128(newTotalAssets);
    _totalShares = SafeCast.toUint128(totalShares_ + treasuryShares);
    emit StateUpdated(profitAccrued, treasuryShares, treasuryAssets);
  }

  /**
   * @dev Internal conversion function (from assets to shares) with support for rounding direction.
   */
  function _convertToShares(
    uint256 assets,
    uint256 totalShares_,
    uint256 totalAssets_,
    Math.Rounding rounding
  ) internal pure returns (uint256 shares) {
    // Will revert if assets > 0, totalShares > 0 and totalAssets = 0.
    // That corresponds to a case where any asset would represent an infinite amount of shares.
    return
      (assets == 0 || totalShares_ == 0)
        ? assets
        : Math.mulDiv(assets, totalShares_, totalAssets_, rounding);
  }

  /**
   * @dev Internal conversion function (from shares to assets) with support for rounding direction.
   */
  function _convertToAssets(
    uint256 shares,
    uint256 totalShares_,
    uint256 totalAssets_,
    Math.Rounding rounding
  ) internal pure returns (uint256) {
    return (totalShares_ == 0) ? shares : Math.mulDiv(shares, totalAssets_, totalShares_, rounding);
  }

  /**
   * @dev Internal function for calculating assets accumulated since last update
   */
  function _unclaimedAssets() internal view returns (uint256) {
    // calculate time passed since the last update
    uint256 timeElapsed;
    unchecked {
      // cannot realistically underflow
      timeElapsed = block.timestamp - _lastUpdateTimestamp;
    }
    if (timeElapsed == 0) return 0;
    return Math.mulDiv(avgRewardPerSecond * _totalAssets, timeElapsed, _wad);
  }
}
