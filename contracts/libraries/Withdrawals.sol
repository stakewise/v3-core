// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';

/**
 * @title Withdrawals
 * @author StakeWise
 * @notice Withdrawals represent checkpoints of assets that were withdrawn
 */
library Withdrawals {
  /**
   * @notice A struct containing withdrawals checkpoint data
   * @param withdrawalId The cumulative number of shares that were withdrawn
   * @param withdrawnAssets The assets that were withdrawn since last checkpoint
   */
  struct Checkpoint {
    uint160 withdrawalId;
    uint96 withdrawnAssets;
  }

  /**
   * @notice A struct containing the history of checkpoints data
   * @param checkpoints An array of withdrawal checkpoints
   */
  struct History {
    Checkpoint[] checkpoints;
  }

  /**
   * @notice Event emitted when checkpoint is created
   * @param withdrawalId The cumulative number of withdrawn shares
   * @param assets The number of assets withdrawn
   **/
  event CheckpointCreated(uint160 withdrawalId, uint96 assets);

  error InvalidCheckpointData();
  error InvalidWithdrawalId();

  /**
   * @notice Get latest withdrawal checkpoint
   * @param self An array containing withdrawal checkpoints
   * @return The latest withdrawal checkpoint ID or zero if there are no checkpoints
   */
  function latestWithdrawalId(History storage self) internal view returns (uint256) {
    uint256 pos = self.checkpoints.length;
    unchecked {
      // cannot underflow as subtraction happens in case pos > 0
      return pos == 0 ? 0 : self.checkpoints[pos - 1].withdrawalId;
    }
  }

  /**
   * @notice Get checkpoint index for the withdrawal ID
   * @param self An array containing withdrawal checkpoints
   * @param withdrawalId The withdrawal ID to search the closest checkpoint for
   * @return high The checkpoint index or the length of checkpoints array in case there is no such
   */
  function getCheckpointIndex(History storage self, uint256 withdrawalId)
    internal
    view
    returns (uint256 high)
  {
    high = self.checkpoints.length;
    uint256 low;
    while (low < high) {
      uint256 mid = Math.average(low, high);
      if (self.checkpoints[mid].withdrawalId >= withdrawalId) {
        high = mid;
      } else {
        unchecked {
          // cannot overflow as it is capped with checkpoints array length
          low = mid + 1;
        }
      }
    }
  }

  /**
   * @notice Calculates the withdrawal
   * @param self An array containing withdrawal checkpoints
   * @param checkpointIdx The index of the checkpoint to start calculating withdrawals from
   * @param withdrawalId The ID to calculate the withdrawal for
   * @param requiredShares The number of shares that needs to be withdrawn
   * @return withdrawnShares The number of shares withdrawn
   * @return withdrawnAssets The number of assets withdrawn
   */
  function calculateWithdrawal(
    History storage self,
    uint256 checkpointIdx,
    uint256 withdrawalId,
    uint256 requiredShares
  ) internal view returns (uint256 withdrawnShares, uint256 withdrawnAssets) {
    uint256 length = self.checkpoints.length;
    // shares are not withdrawn yet
    if (checkpointIdx >= length || requiredShares == 0) return (0, 0);

    // previous withdrawal ID for calculating how much shares were withdrawn for the period
    uint256 prevWithdrawalId;
    unchecked {
      // cannot underflow as subtraction happens in case checkpointIdx > 0
      prevWithdrawalId = checkpointIdx == 0 ? 0 : self.checkpoints[checkpointIdx - 1].withdrawalId;
    }

    // current withdrawal ID for calculating assets per withdrawn shares
    Checkpoint storage checkpoint = self.checkpoints[checkpointIdx];
    uint256 currWithdrawalId = checkpoint.withdrawalId;
    uint256 periodWithdrawnAssets = checkpoint.withdrawnAssets;
    if (withdrawalId <= prevWithdrawalId || currWithdrawalId < withdrawalId) {
      revert InvalidWithdrawalId();
    }

    // accumulate assets until required shares are withdrawn
    uint256 periodWithdrawnShares;
    uint256 sharesDelta;
    while (true) {
      unchecked {
        // cannot underflow as every next checkpoint ID is higher than the previous one
        periodWithdrawnShares = currWithdrawalId - prevWithdrawalId;
        // cannot underflow as requiredShares > withdrawnShares while in the loop
        sharesDelta = Math.min(periodWithdrawnShares, requiredShares - withdrawnShares);

        // cannot overflow as it is capped with staked asset total supply
        withdrawnShares += sharesDelta;
        withdrawnAssets += Math.mulDiv(sharesDelta, periodWithdrawnAssets, periodWithdrawnShares);

        // cannot overflow as it is capped with checkpoints array length
        checkpointIdx++;
      }
      // stop when required shares withdrawn or reached end of checkpoints list
      if (requiredShares == withdrawnShares || checkpointIdx == length) {
        return (withdrawnShares, withdrawnAssets);
      }

      // take next checkpoint
      prevWithdrawalId = currWithdrawalId;
      checkpoint = self.checkpoints[checkpointIdx];
      currWithdrawalId = checkpoint.withdrawalId;
      periodWithdrawnAssets = checkpoint.withdrawnAssets;
    }
  }

  /**
   * @notice Pushes a new checkpoint onto a History
   * @param self An array containing withdrawal checkpoints
   * @param shares The number of shares to add to the latest withdrawal ID
   * @param assets The number of assets that were withdrawn for this checkpoint
   */
  function push(
    History storage self,
    uint256 shares,
    uint256 assets
  ) internal {
    if (shares == 0 || assets == 0) revert InvalidCheckpointData();
    Checkpoint memory checkpoint = Checkpoint({
      withdrawalId: SafeCast.toUint160(latestWithdrawalId(self) + shares),
      withdrawnAssets: SafeCast.toUint96(assets)
    });
    self.checkpoints.push(checkpoint);
    emit CheckpointCreated(checkpoint.withdrawalId, checkpoint.withdrawnAssets);
  }
}
