// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';

/// Custom errors
error InvalidCheckpointIndex();
error InvalidCheckpointValue();

/**
 * @title ExitQueue
 * @author StakeWise
 * @notice ExitQueue represent checkpoints of burned shares and exited assets
 */
library ExitQueue {
  /**
   * @notice A struct containing checkpoint data
   * @param totalTickets The cumulative number of tickets (shares) exited
   * @param exitedAssets The number of assets that exited in this checkpoint
   */
  struct Checkpoint {
    uint160 totalTickets;
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
   * @notice Get the latest checkpoint total tickets
   * @param self An array containing checkpoints
   * @return The current total tickets or zero if there are no checkpoints
   */
  function getLatestTotalTickets(History storage self) internal view returns (uint256) {
    uint256 pos = self.checkpoints.length;
    unchecked {
      // cannot underflow as subtraction happens in case pos > 0
      return pos == 0 ? 0 : _unsafeAccess(self.checkpoints, pos - 1).totalTickets;
    }
  }

  /**
   * @notice Get checkpoint index for the burned shares
   * @param self An array containing checkpoints
   * @param positionTicket The position ticket to search the closest checkpoint for
   * @return The checkpoint index or the length of checkpoints array in case there is no such
   */
  function getCheckpointIndex(
    History storage self,
    uint256 positionTicket
  ) internal view returns (uint256) {
    uint256 high = self.checkpoints.length;
    uint256 low;
    while (low < high) {
      uint256 mid = Math.average(low, high);
      if (_unsafeAccess(self.checkpoints, mid).totalTickets > positionTicket) {
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
   * @param positionTicket The position to start calculating exited assets from
   * @param positionShares The number of shares to calculate assets for
   * @return burnedShares The number of shares burned
   * @return exitedAssets The number of assets exited
   */
  function calculateExitedAssets(
    History storage self,
    uint256 checkpointIdx,
    uint256 positionTicket,
    uint256 positionShares
  ) internal view returns (uint256 burnedShares, uint256 exitedAssets) {
    uint256 length = self.checkpoints.length;
    // there are no exited assets for such checkpoint index or no shares to burn
    if (checkpointIdx >= length || positionShares == 0) return (0, 0);

    // previous total tickets for calculating how much shares were burned for the period
    uint256 prevTotalTickets;
    unchecked {
      // cannot underflow as subtraction happens in case checkpointIdx > 0
      prevTotalTickets = checkpointIdx == 0
        ? 0
        : _unsafeAccess(self.checkpoints, checkpointIdx - 1).totalTickets;
    }

    // current total tickets for calculating assets per burned share
    // can be used with _unsafeAccess as checkpointIdx < length
    Checkpoint memory checkpoint = _unsafeAccess(self.checkpoints, checkpointIdx);
    uint256 currTotalTickets = checkpoint.totalTickets;
    uint256 checkpointAssets = checkpoint.exitedAssets;
    // check whether position ticket is in [prevTotalTickets, currTotalTickets) range
    if (positionTicket < prevTotalTickets || currTotalTickets <= positionTicket) {
      revert InvalidCheckpointIndex();
    }

    // calculate amount of available shares that will be updated while iterating over checkpoints
    uint256 availableShares;
    unchecked {
      // cannot underflow as positionTicket < currTotalTickets
      availableShares = currTotalTickets - positionTicket;
    }

    // accumulate assets until the number of required shares is collected
    uint256 checkpointShares;
    uint256 sharesDelta;
    while (true) {
      unchecked {
        // cannot underflow as prevTotalTickets <= positionTicket
        checkpointShares = currTotalTickets - prevTotalTickets;
        // cannot underflow as positionShares > burnedShares while in the loop
        sharesDelta = Math.min(availableShares, positionShares - burnedShares);

        // cannot overflow as it is capped with underlying asset total supply
        burnedShares += sharesDelta;
        exitedAssets += Math.mulDiv(sharesDelta, checkpointAssets, checkpointShares);
      }
      checkpointIdx++;

      // stop when required shares collected or reached end of checkpoints list
      if (positionShares <= burnedShares || checkpointIdx >= length) {
        return (burnedShares, exitedAssets);
      }

      // take next checkpoint
      prevTotalTickets = currTotalTickets;
      // can use _unsafeAccess as checkpointIdx < length is checked above
      checkpoint = _unsafeAccess(self.checkpoints, checkpointIdx);
      currTotalTickets = checkpoint.totalTickets;
      checkpointAssets = checkpoint.exitedAssets;

      unchecked {
        // cannot underflow as every next checkpoint total tickets is larger than previous
        availableShares = currTotalTickets - prevTotalTickets;
      }
    }
  }

  /**
   * @notice Pushes a new checkpoint onto a History
   * @param self An array containing checkpoints
   * @param shares The number of shares to add to the latest checkpoint
   * @param assets The number of assets that were exited for this checkpoint
   */
  function push(History storage self, uint256 shares, uint256 assets) internal {
    if (shares == 0 || assets == 0) revert InvalidCheckpointValue();
    Checkpoint memory checkpoint = Checkpoint({
      totalTickets: SafeCast.toUint160(getLatestTotalTickets(self) + shares),
      exitedAssets: SafeCast.toUint96(assets)
    });
    self.checkpoints.push(checkpoint);
  }

  function _unsafeAccess(
    Checkpoint[] storage self,
    uint256 pos
  ) private pure returns (Checkpoint storage result) {
    assembly {
      mstore(0, self.slot)
      result.slot := add(keccak256(0, 0x20), pos)
    }
  }
}
