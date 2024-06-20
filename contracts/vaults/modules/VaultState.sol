// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {IVaultState} from '../../interfaces/IVaultState.sol';
import {IKeeperRewards} from '../../interfaces/IKeeperRewards.sol';
import {ExitQueue} from '../../libraries/ExitQueue.sol';
import {Errors} from '../../libraries/Errors.sol';
import {VaultImmutables} from './VaultImmutables.sol';
import {VaultFee} from './VaultFee.sol';

/**
 * @title VaultState
 * @author StakeWise
 * @notice Defines Vault's state manipulation
 */
abstract contract VaultState is VaultImmutables, Initializable, VaultFee, IVaultState {
  using ExitQueue for ExitQueue.History;

  uint128 internal _totalShares;
  uint128 internal _totalAssets;

  /// @inheritdoc IVaultState
  uint128 public override queuedShares; // deprecated
  uint128 internal _unclaimedAssets; // deprecated
  ExitQueue.History internal _exitQueue; // deprecated

  mapping(bytes32 => uint256) internal _exitRequests;
  mapping(address => uint256) internal _balances;

  uint256 private _capacity;

  /// @inheritdoc IVaultState
  uint128 public override totalExitingAssets;
  uint128 internal _totalExitingTickets;
  uint256 internal _totalExitedTickets;

  /// @inheritdoc IVaultState
  function totalShares() external view override returns (uint256) {
    return _totalShares;
  }

  /// @inheritdoc IVaultState
  function totalAssets() external view override returns (uint256) {
    return _totalAssets;
  }

  /// @inheritdoc IVaultState
  function getShares(address account) external view override returns (uint256) {
    return _balances[account];
  }

  /// @inheritdoc IVaultState
  function convertToShares(uint256 assets) public view override returns (uint256 shares) {
    return _convertToShares(assets, Math.Rounding.Floor);
  }

  /// @inheritdoc IVaultState
  function convertToAssets(uint256 shares) public view override returns (uint256 assets) {
    uint256 totalShares_ = _totalShares;
    return (totalShares_ == 0) ? shares : Math.mulDiv(shares, _totalAssets, totalShares_);
  }

  /// @inheritdoc IVaultState
  function capacity() public view override returns (uint256) {
    // SLOAD to memory
    uint256 capacity_ = _capacity;

    // if capacity is not set, it is unlimited
    return capacity_ == 0 ? type(uint256).max : capacity_;
  }

  /// @inheritdoc IVaultState
  function withdrawableAssets() public view override returns (uint256) {
    uint256 vaultAssets = _vaultAssets();
    unchecked {
      // calculate assets that are reserved by users who queued for exit
      // cannot overflow as it is capped with underlying asset total supply
      uint256 reservedAssets = totalExitingAssets + _unclaimedAssets;
      return vaultAssets > reservedAssets ? vaultAssets - reservedAssets : 0;
    }
  }

  /// @inheritdoc IVaultState
  function isStateUpdateRequired() external view override returns (bool) {
    return IKeeperRewards(_keeper).isHarvestRequired(address(this));
  }

  /// @inheritdoc IVaultState
  function updateState(
    IKeeperRewards.HarvestParams calldata harvestParams
  ) public virtual override {
    // process total assets delta  since last update
    int256 totalAssetsDelta = _harvestAssets(harvestParams);

    // process total assets delta if it has changed
    _processTotalAssetsDelta(totalAssetsDelta);
  }

  /**
   * @dev Internal function for processing rewards and penalties
   * @param totalAssetsDelta The number of assets earned or lost
   */
  function _processTotalAssetsDelta(int256 totalAssetsDelta) internal virtual {
    // skip processing if there is no change in assets
    if (totalAssetsDelta == 0) return;

    // SLOAD to memory
    uint256 newTotalAssets = _totalAssets;
    if (totalAssetsDelta < 0) {
      uint256 penalty = uint256(-totalAssetsDelta);

      // SLOAD to memory
      uint256 _totalExitingAssets = totalExitingAssets;
      if (_totalExitingAssets > 0) {
        // apply penalty to exiting assets
        uint256 exitingAssetsPenalty = Math.mulDiv(
          penalty,
          _totalExitingAssets,
          _totalExitingAssets + newTotalAssets
        );

        // apply penalty to total exiting assets
        unchecked {
          // cannot underflow as exitingAssetsPenalty <= penalty
          penalty -= exitingAssetsPenalty;
          // cannot underflow as exitingAssetsPenalty <= _totalExitingAssets
          totalExitingAssets = SafeCast.toUint128(_totalExitingAssets - exitingAssetsPenalty);
        }
      }

      // subtract penalty from total assets (excludes exiting assets)
      if (penalty > 0) {
        _totalAssets = SafeCast.toUint128(newTotalAssets - penalty);
      }
      return;
    }

    // convert assets delta as it is positive
    uint256 profitAssets = uint256(totalAssetsDelta);
    newTotalAssets += profitAssets;

    // update state
    _totalAssets = SafeCast.toUint128(newTotalAssets);

    // calculate admin fee recipient assets
    uint256 feeRecipientAssets = Math.mulDiv(profitAssets, feePercent, _maxFeePercent);
    if (feeRecipientAssets == 0) return;

    // SLOAD to memory
    uint256 totalShares_ = _totalShares;

    // calculate fee recipient's shares
    uint256 feeRecipientShares;
    if (totalShares_ == 0) {
      feeRecipientShares = feeRecipientAssets;
    } else {
      unchecked {
        feeRecipientShares = Math.mulDiv(
          feeRecipientAssets,
          totalShares_,
          newTotalAssets - feeRecipientAssets
        );
      }
    }

    // SLOAD to memory
    address _feeRecipient = feeRecipient;
    // mint shares to the fee recipient
    _mintShares(_feeRecipient, feeRecipientShares);
    emit FeeSharesMinted(_feeRecipient, feeRecipientShares, feeRecipientAssets);
  }

  /**
   * @dev Internal function for minting shares
   * @param owner The address of the owner to mint shares to
   * @param shares The number of shares to mint
   */
  function _mintShares(address owner, uint256 shares) internal virtual {
    // update total shares
    _totalShares += SafeCast.toUint128(shares);

    // mint shares
    unchecked {
      // cannot overflow because the sum of all user
      // balances can't exceed the max uint256 value
      _balances[owner] += shares;
    }
  }

  /**
   * @dev Internal function for burning shares
   * @param owner The address of the owner to burn shares for
   * @param shares The number of shares to burn
   */
  function _burnShares(address owner, uint256 shares) internal virtual {
    // burn shares
    _balances[owner] -= shares;

    // update total shares
    unchecked {
      // cannot underflow because the sum of all shares can't exceed the _totalShares
      _totalShares -= SafeCast.toUint128(shares);
    }
  }

  /**
   * @dev Internal conversion function (from assets to shares) with support for rounding direction.
   */
  function _convertToShares(
    uint256 assets,
    Math.Rounding rounding
  ) internal view returns (uint256 shares) {
    uint256 totalShares_ = _totalShares;
    // Will revert if assets > 0, totalShares > 0 and _totalAssets = 0.
    // That corresponds to a case where any asset would represent an infinite amount of shares.
    return
      (assets == 0 || totalShares_ == 0)
        ? assets
        : Math.mulDiv(assets, totalShares_, _totalAssets, rounding);
  }

  /**
   * @dev Internal conversion function (from assets to exit tickets)
   */
  function _convertAssetsToExitTickets(uint256 assets) internal view returns (uint256 exitTickets) {
    uint256 totalExitingTickets = _totalExitingTickets;
    // Will revert if assets > 0, totalExitingTickets > 0 and totalExitingAssets = 0.
    // That corresponds to a case where any asset would represent an infinite amount of tickets.
    return
      (assets == 0 || totalExitingTickets == 0)
        ? assets
        : Math.mulDiv(assets, totalExitingTickets, totalExitingAssets, Math.Rounding.Floor);
  }

  /**
   * @dev Internal conversion function (from exit tickets to assets)
   */
  function _convertExitTicketsToAssets(uint256 exitTickets) internal view returns (uint256 assets) {
    uint256 totalExitingTickets = _totalExitingTickets;
    return
      (totalExitingTickets == 0)
        ? exitTickets
        : Math.mulDiv(exitTickets, totalExitingAssets, totalExitingTickets);
  }

  /**
   * @dev Internal function for harvesting Vaults' new assets
   * @return The total assets delta after harvest
   */
  function _harvestAssets(
    IKeeperRewards.HarvestParams calldata harvestParams
  ) internal virtual returns (int256);

  /**
   * @dev Internal function for retrieving the total assets stored in the Vault.
   *       NB! Assets can be forcibly sent to the vault, the returned value must be used with caution
   * @return The total amount of assets stored in the Vault
   */
  function _vaultAssets() internal view virtual returns (uint256);

  /**
   * @dev Initializes the VaultState contract
   * @param capacity_ The amount after which the Vault stops accepting deposits
   */
  function __VaultState_init(uint256 capacity_) internal onlyInitializing {
    if (capacity_ == 0) revert Errors.InvalidCapacity();
    // skip setting capacity if it is unlimited
    if (capacity_ != type(uint256).max) _capacity = capacity_;
  }

  /**
   * @dev Initializes the VaultState contract V3
   */
  function __VaultState_initV3() internal view onlyInitializing {
    if (queuedShares > 1) revert Errors.UpgradeFailed();
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[48] private __gap;
}
