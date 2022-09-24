// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';

/**
 * @title ExitQueue
 * @author StakeWise
 * @notice ExitQueue represent checkpoints of burned shares and exited assets
 */
library ExitQueue {
  /**
   * @notice A struct containing checkpoint data
   * @param sharesCounter The cumulative number of burned shares
   * @param exitedAssets The number of assets that exited in this checkpoint
   */
  struct Checkpoint {
    uint160 sharesCounter;
    uint96 exitedAssets;
  }

  /**
   * @notice A struct containing the history of checkpoints data
   * @param checkpoints An array of checkpoints
   */
  struct History {
    Checkpoint[] checkpoints;
  }

  /**
   * @notice Event emitted on checkpoint creation
   * @param sharesCounter The cumulative number of burned shares
   * @param exitedAssets The amount of exited assets
   */
  event CheckpointCreated(uint160 sharesCounter, uint96 exitedAssets);

  error InvalidCheckpointIndex();

  /**
   * @notice Get the current burned shares counter
   * @param self An array containing checkpoints
   * @return The current shares counter or zero if there are no checkpoints
   */
  function getSharesCounter(History storage self) internal view returns (uint256) {
    uint256 pos = self.checkpoints.length;
    unchecked {
      // cannot underflow as subtraction happens in case pos > 0
      return pos == 0 ? 0 : _unsafeAccess(self.checkpoints, pos - 1).sharesCounter;
    }
  }

  /**
   * @notice Get checkpoint index for the burned shares counter
   * @param self An array containing checkpoints
   * @param sharesCounter The shares counter to search the closest checkpoint for
   * @return The checkpoint index or the length of checkpoints array in case there is no such
   */
  function getCheckpointIndex(History storage self, uint256 sharesCounter)
    internal
    view
    returns (uint256)
  {
    uint256 high = self.checkpoints.length;
    uint256 low;
    while (low < high) {
      uint256 mid = Math.average(low, high);
      if (_unsafeAccess(self.checkpoints, mid).sharesCounter > sharesCounter) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return high;
  }

  /**
   * @notice Calculates burned shares and exited assets
   * @param self An array containing checkpoints
   * @param checkpointIdx The index of the checkpoint to start calculating from
   * @param sharesCounter The shares counter to start calculating exited assets from
   * @param requiredShares The number of shares to calculate assets for
   * @return burnedShares The number of shares burned
   * @return exitedAssets The number of assets exited
   */
  function calculateExitedAssets(
    History storage self,
    uint256 checkpointIdx,
    uint256 sharesCounter,
    uint256 requiredShares
  ) internal view returns (uint256 burnedShares, uint256 exitedAssets) {
    uint256 length = self.checkpoints.length;
    // there are no exited assets for such checkpoint index or no shares to burn
    if (checkpointIdx >= length || requiredShares == 0) return (0, 0);

    // previous shares counter for calculating how much shares were burned for the period
    uint256 prevCounter;
    unchecked {
      // cannot underflow as subtraction happens in case checkpointIdx > 0
      prevCounter = checkpointIdx == 0
        ? 0
        : _unsafeAccess(self.checkpoints, checkpointIdx - 1).sharesCounter;
    }

    // current shares counter for calculating assets per burned share
    Checkpoint storage checkpoint = _unsafeAccess(self.checkpoints, checkpointIdx);
    uint256 currCounter = checkpoint.sharesCounter;
    uint256 checkpointAssets = checkpoint.exitedAssets;
    if (sharesCounter < prevCounter || currCounter <= sharesCounter) {
      revert InvalidCheckpointIndex();
    }

    // calculate amount of available shares that will be updated while iterating over checkpoints
    uint256 availableShares;
    unchecked {
      // cannot underflow as every next checkpoint counter is larger than previous
      availableShares = currCounter - sharesCounter;
    }

    // accumulate assets until the number of required shares is collected
    uint256 checkpointShares;
    uint256 sharesDelta;
    while (true) {
      unchecked {
        // cannot underflow as every next checkpoint counter is larger than previous
        checkpointShares = currCounter - prevCounter;
        // cannot underflow as requiredShares > burnedShares while in the loop
        sharesDelta = Math.min(availableShares, requiredShares - burnedShares);

        // cannot overflow as it is capped with staked asset total supply
        burnedShares += sharesDelta;
        exitedAssets += Math.mulDiv(sharesDelta, checkpointAssets, checkpointShares);

        // cannot overflow as it is capped with checkpoints array length
        checkpointIdx++;
      }
      // stop when required shares collected or reached end of checkpoints list
      if (requiredShares == burnedShares || checkpointIdx == length) {
        return (burnedShares, exitedAssets);
      }

      // take next checkpoint
      prevCounter = currCounter;
      checkpoint = _unsafeAccess(self.checkpoints, checkpointIdx);
      currCounter = checkpoint.sharesCounter;
      checkpointAssets = checkpoint.exitedAssets;

      unchecked {
        // cannot underflow as every next checkpoint counter is larger than previous
        availableShares = currCounter - prevCounter;
      }
    }
  }

  /**
   * @notice Pushes a new checkpoint onto a History
   * @param self An array containing checkpoints
   * @param shares The number of shares to add to the latest shares counter
   * @param assets The number of assets that were exited for this checkpoint
   */
  function push(
    History storage self,
    uint256 shares,
    uint256 assets
  ) internal {
    Checkpoint memory checkpoint = Checkpoint({
      sharesCounter: SafeCast.toUint160(getSharesCounter(self) + shares),
      exitedAssets: SafeCast.toUint96(assets)
    });
    self.checkpoints.push(checkpoint);
    emit CheckpointCreated(checkpoint.sharesCounter, checkpoint.exitedAssets);
  }

  function _unsafeAccess(Checkpoint[] storage self, uint256 pos)
    private
    pure
    returns (Checkpoint storage result)
  {
    assembly {
      mstore(0, self.slot)
      result.slot := add(keccak256(0, 0x20), pos)
    }
  }
}
