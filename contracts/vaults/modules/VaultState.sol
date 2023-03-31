// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

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
  function getCheckpointIndex(uint256 positionCounter) external view override returns (int256) {
    uint256 checkpointIdx = _exitQueue.getCheckpointIndex(positionCounter);
    return checkpointIdx < _exitQueue.checkpoints.length ? int256(checkpointIdx) : -1;
  }

  /// @inheritdoc IVaultState
  function canUpdateExitQueue() public view override returns (bool) {
    return block.timestamp >= _exitQueueNextUpdate;
  }

  /// @inheritdoc IVaultState
  function updateState(IKeeperRewards.HarvestParams calldata harvestParams) public override {
    // process total assets delta  since last update
    int256 totalAssetsDelta = _harvestAssets(harvestParams);
    if (totalAssetsDelta != 0) _processTotalAssetsDelta(totalAssetsDelta);

    // update exit queue
    if (canUpdateExitQueue()) {
      _updateExitQueue();
    }
  }

  /**
   * @dev Internal function for processing rewards and penalties
   * @param totalAssetsDelta The number of assets earned or lost
   */
  function _processTotalAssetsDelta(int256 totalAssetsDelta) internal {
    // SLOAD to memory
    uint256 newTotalAssets = _totalAssets;
    if (totalAssetsDelta < 0) {
      // add penalty to total assets
      newTotalAssets -= uint256(-totalAssetsDelta);

      // update state
      _totalAssets = SafeCast.toUint128(newTotalAssets);
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
    uint256 totalShares = _totalShares;

    // calculate fee recipient's shares
    uint256 feeRecipientShares;
    unchecked {
      // cannot underflow as feePercent <= maxFeePercent
      feeRecipientShares = _convertToShares(
        feeRecipientAssets,
        totalShares,
        newTotalAssets - feeRecipientAssets,
        Math.Rounding.Down
      );
    }
    if (feeRecipientShares == 0) return;

    // update state
    _totalShares = SafeCast.toUint128(totalShares + feeRecipientShares);

    // SLOAD to memory
    address _feeRecipient = feeRecipient;

    // mint shares to the fee recipient
    unchecked {
      // cannot underflow because the sum of all shares can't exceed the _totalShares
      balanceOf[_feeRecipient] += feeRecipientShares;
    }
    emit Transfer(address(0), _feeRecipient, feeRecipientShares);
  }

  /**
   * @dev Internal function that must be used to process exit queue
   */
  function _updateExitQueue() internal {
    // SLOAD to memory
    uint256 _queuedShares = queuedShares;
    if (_queuedShares == 0) return;

    // calculate the amount of assets that can be exited
    uint256 _unclaimedAssets = unclaimedAssets;
    uint256 exitedAssets = Math.min(
      _vaultAssets() - _unclaimedAssets,
      convertToAssets(_queuedShares)
    );
    if (exitedAssets == 0) return;

    // calculate the amount of shares that can be burned
    uint256 burnedShares = convertToShares(exitedAssets);
    if (burnedShares == 0) return;

    queuedShares = SafeCast.toUint96(_queuedShares - burnedShares);
    unclaimedAssets = SafeCast.toUint96(_unclaimedAssets + exitedAssets);

    unchecked {
      // cannot overflow on human timescales
      _exitQueueNextUpdate = uint64(block.timestamp + _exitQueueUpdateDelay);
    }

    // push checkpoint so that exited assets could be claimed
    _exitQueue.push(burnedShares, exitedAssets);
    emit CheckpointCreated(burnedShares, exitedAssets);

    // update state
    _totalShares -= SafeCast.toUint128(burnedShares);
    _totalAssets -= SafeCast.toUint128(exitedAssets);

    // emit burn event
    emit Transfer(address(this), address(0), burnedShares);
  }

  /**
   * @dev Internal function for harvesting Vaults' new assets
   * @return The total assets delta after harvest
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
