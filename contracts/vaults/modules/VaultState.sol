// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {IVaultState} from '../../interfaces/IVaultState.sol';
import {IKeeperRewards} from '../../interfaces/IKeeperRewards.sol';
import {ExitQueue} from '../../libraries/ExitQueue.sol';
import {VaultImmutables} from './VaultImmutables.sol';
import {VaultToken} from './VaultToken.sol';
import {VaultFee} from './VaultFee.sol';

/**
 * @title VaultState
 * @author StakeWise
 * @notice Defines Vault's state manipulation
 */
abstract contract VaultState is VaultImmutables, Initializable, VaultToken, VaultFee, IVaultState {
  using ExitQueue for ExitQueue.History;

  uint256 internal constant _exitQueueUpdateDelay = 1 days;

  /// @inheritdoc IVaultState
  uint96 public override queuedShares;

  /// @inheritdoc IVaultState
  uint96 public override unclaimedAssets;

  uint64 internal _exitQueueNextUpdate;

  ExitQueue.History internal _exitQueue;
  mapping(bytes32 => uint256) internal _exitRequests;

  /// @inheritdoc IVaultState
  function withdrawableAssets() public view override returns (uint256) {
    uint256 vaultAssets = _vaultAssets();
    unchecked {
      // calculate assets that are reserved by users who queued for exit
      // cannot overflow as it is capped with underlying asset total supply
      uint256 reservedAssets = convertToAssets(queuedShares) + unclaimedAssets;
      return vaultAssets > reservedAssets ? vaultAssets - reservedAssets : 0;
    }
  }

  /// @inheritdoc IVaultState
  function redeemableShares() public view override returns (uint256) {
    return convertToShares(withdrawableAssets());
  }

  /// @inheritdoc IVaultState
  function getCheckpointIndex(uint256 exitQueueId) external view override returns (int256) {
    uint256 checkpointIdx = _exitQueue.getCheckpointIndex(exitQueueId);
    return checkpointIdx < _exitQueue.checkpoints.length ? int256(checkpointIdx) : -1;
  }

  /// @inheritdoc IVaultState
  function updateState(IKeeperRewards.HarvestParams calldata harvestParams) public override {
    // can be negative in case of the loss
    int256 assetsDelta = _harvestAssets(harvestParams);

    // SLOAD to memory
    uint256 totalAssetsAfter = _totalAssets;
    uint256 totalSharesAfter = _totalShares;

    if (assetsDelta > 0) {
      // compute fees as the fee percent multiplied by the profit
      uint256 profitAccrued = uint256(assetsDelta);

      // increase total staked amount
      totalAssetsAfter += profitAccrued;

      // SLOAD to memory
      uint256 _feePercent = feePercent;
      if (_feePercent > 0) {
        // calculate fee recipient's shares
        uint256 feeRecipientAssets = Math.mulDiv(profitAccrued, _feePercent, _maxFeePercent);

        // Will revert if totalAssetsAfter - feeRecipientAssets = 0.
        // That corresponds to a case where any asset would represent an infinite amount of shares.
        uint256 feeRecipientShares;
        unchecked {
          // cannot underflow as feePercent <= maxFeePercent
          feeRecipientShares = Math.mulDiv(
            feeRecipientAssets,
            totalSharesAfter,
            totalAssetsAfter - feeRecipientAssets
          );
        }

        if (feeRecipientShares > 0) {
          // SLOAD to memory
          address _feeRecipient = feeRecipient;
          // mint shares to the fee recipient
          totalSharesAfter += feeRecipientShares;
          unchecked {
            // cannot underflow because the sum of all shares can't exceed the _totalShares
            balanceOf[_feeRecipient] += feeRecipientShares;
          }
          emit Transfer(address(0), _feeRecipient, feeRecipientShares);
        }
      }
    } else if (assetsDelta < 0) {
      // apply penalty
      totalAssetsAfter -= uint256(-assetsDelta);
    }

    // update storage values
    if (assetsDelta != 0) {
      _totalShares = SafeCast.toUint128(totalSharesAfter);
      _totalAssets = SafeCast.toUint128(totalAssetsAfter);
      emit StateUpdated(assetsDelta);
    }

    // update exit queue
    (uint256 burnedShares, uint256 exitedAssets) = _updateExitQueue();
    if (burnedShares > 0) {
      _totalShares -= SafeCast.toUint128(burnedShares);
      _totalAssets -= SafeCast.toUint128(exitedAssets);
    }
  }

  /**
   * @dev Internal function that must be used to process exit queue
   * @return burnedShares The amount of shares that must be deducted from total shares
   * @return exitedAssets The amount of assets that must be deducted from total assets
   */
  function _updateExitQueue() internal returns (uint256 burnedShares, uint256 exitedAssets) {
    if (block.timestamp < _exitQueueNextUpdate) return (0, 0);

    // SLOAD to memory
    uint256 _queuedShares = queuedShares;
    if (_queuedShares == 0) return (0, 0);

    // calculate the amount of assets that can be exited
    uint256 _unclaimedAssets = unclaimedAssets;
    unchecked {
      // cannot underflow as _vaultAssets() >= _unclaimedAssets
      exitedAssets = Math.min(_vaultAssets() - _unclaimedAssets, convertToAssets(_queuedShares));
    }

    // calculate the amount of shares that can be burned
    burnedShares = convertToShares(exitedAssets);
    if (burnedShares == 0 || exitedAssets == 0) return (0, 0);

    unchecked {
      // cannot underflow as queuedShares >= burnedShares
      queuedShares = SafeCast.toUint96(_queuedShares - burnedShares);

      // cannot overflow as it is capped with underlying asset total supply
      unclaimedAssets = SafeCast.toUint96(_unclaimedAssets + exitedAssets);

      // cannot overflow on human timescales
      _exitQueueNextUpdate = uint64(block.timestamp + _exitQueueUpdateDelay);
    }

    // emit burn event
    emit Transfer(address(this), address(0), burnedShares);

    // push checkpoint so that exited assets could be claimed
    _exitQueue.push(burnedShares, exitedAssets);
  }

  /**
   * @dev Internal function for harvesting Vaults' new assets
   * @return The number of assets earned or lost
   */
  function _harvestAssets(
    IKeeperRewards.HarvestParams calldata harvestParams
  ) internal virtual returns (int256);

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
