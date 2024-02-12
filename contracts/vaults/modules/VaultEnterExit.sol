// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {IKeeperRewards} from '../../interfaces/IKeeperRewards.sol';
import {IVaultEnterExit} from '../../interfaces/IVaultEnterExit.sol';
import {ExitQueue} from '../../libraries/ExitQueue.sol';
import {Errors} from '../../libraries/Errors.sol';
import {VaultImmutables} from './VaultImmutables.sol';
import {VaultState} from './VaultState.sol';

/**
 * @title VaultEnterExit
 * @author StakeWise
 * @notice Defines the functionality for entering and exiting the Vault
 */
abstract contract VaultEnterExit is VaultImmutables, Initializable, VaultState, IVaultEnterExit {
  using ExitQueue for ExitQueue.History;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  uint256 private immutable _exitingAssetsClaimDelay;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param exitingAssetsClaimDelay The minimum delay after which the assets can be claimed after joining the exit queue
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(uint256 exitingAssetsClaimDelay) {
    _exitingAssetsClaimDelay = exitingAssetsClaimDelay;
  }

  /// @inheritdoc IVaultEnterExit
  function getExitQueueIndex(uint256 positionTicket) external view override returns (int256) {
    if (_exitQueue.isV1Position(_queuedShares, positionTicket)) {
      uint256 checkpointIdx = _exitQueue.getCheckpointIndex(positionTicket);
      return checkpointIdx < _exitQueue.checkpoints.length ? int256(checkpointIdx) : -1;
    }
    // calculate total exited tickets
    uint256 totalExitedTickets = _totalExitedTickets + _getTotalExitableTickets();
    return (totalExitedTickets > positionTicket) ? int256(0) : -1;
  }

  /// @inheritdoc IVaultEnterExit
  function enterExitQueue(
    uint256 shares,
    address receiver
  ) public virtual override returns (uint256 positionTicket) {
    return _enterExitQueue(msg.sender, shares, receiver);
  }

  /// @inheritdoc IVaultEnterExit
  function calculateExitedAssets(
    address receiver,
    uint256 positionTicket,
    uint256 timestamp,
    uint256 exitQueueIndex
  )
    public
    view
    override
    returns (uint256 leftTickets, uint256 exitedTickets, uint256 exitedAssets)
  {
    uint256 exitingTickets = _exitRequests[
      keccak256(abi.encode(receiver, timestamp, positionTicket))
    ];
    if (exitingTickets == 0) return (0, 0, 0);
    if (block.timestamp < timestamp + _exitingAssetsClaimDelay) return (exitingTickets, 0, 0);

    if (_exitQueue.isV1Position(_queuedShares, positionTicket)) {
      // calculate exited assets in V1 exit queue
      (exitedTickets, exitedAssets) = _exitQueue.calculateExitedAssets(
        exitQueueIndex,
        positionTicket,
        exitingTickets
      );
    } else {
      // calculate exited assets
      (exitedTickets, exitedAssets) = _calculateExitedTickets(exitingTickets, positionTicket);
    }
    leftTickets = exitingTickets - exitedTickets;
  }

  /// @inheritdoc IVaultEnterExit
  function claimExitedAssets(
    uint256 positionTicket,
    uint256 timestamp,
    uint256 exitQueueIndex
  ) external override {
    // calculate exited tickets and assets
    (uint256 leftTickets, uint256 exitedTickets, uint256 exitedAssets) = calculateExitedAssets(
      msg.sender,
      positionTicket,
      timestamp,
      exitQueueIndex
    );
    if (exitedTickets == 0 || exitedAssets == 0) revert Errors.ExitRequestNotProcessed();

    if (_exitQueue.isV1Position(_queuedShares, positionTicket)) {
      // update unclaimed assets
      _unclaimedAssets -= SafeCast.toUint128(exitedAssets);
    } else {
      // vault must be harvested to calculate exact withdrawable amount
      _checkHarvested();

      // update state
      totalExitingAssets -= SafeCast.toUint128(exitedAssets);
      _totalExitingTickets -= SafeCast.toUint128(exitedTickets);
      _totalExitedTickets += exitedTickets;
    }

    // clean up current exit request
    delete _exitRequests[keccak256(abi.encode(msg.sender, timestamp, positionTicket))];

    // skip creating new position for the tickets rounding error
    uint256 newPositionTicket;
    if (leftTickets > 1) {
      // update user's queue position
      newPositionTicket = positionTicket + exitedTickets;
      _exitRequests[keccak256(abi.encode(msg.sender, timestamp, newPositionTicket))] = leftTickets;
    }

    // transfer assets to the receiver
    _transferVaultAssets(msg.sender, exitedAssets);
    emit ExitedAssetsClaimed(msg.sender, newPositionTicket, exitedAssets);
  }

  function _calculateExitedTickets(
    uint256 exitingTickets,
    uint256 positionTicket
  ) private view returns (uint256 exitedTickets, uint256 exitedAssets) {
    // calculate total exitable tickets
    uint256 exitableTickets = _getTotalExitableTickets();
    // calculate total exited tickets
    uint256 totalExitedTickets = _totalExitedTickets + exitableTickets;
    if (totalExitedTickets <= positionTicket) return (0, 0);

    // calculate exited tickets and assets
    exitedTickets = Math.min(exitingTickets, totalExitedTickets - positionTicket);
    return (exitedTickets, _convertExitTicketsToAssets(exitedTickets));
  }

  /**
   * @dev Internal function that must be used to process user deposits
   * @param to The address to mint shares to
   * @param assets The number of assets deposited
   * @param referrer The address of the referrer. Set to zero address if not used.
   * @return shares The total amount of shares minted
   */
  function _deposit(
    address to,
    uint256 assets,
    address referrer
  ) internal virtual returns (uint256 shares) {
    _checkHarvested();
    if (to == address(0)) revert Errors.ZeroAddress();
    if (assets == 0) revert Errors.InvalidAssets();

    uint256 totalAssetsAfter;
    unchecked {
      // cannot overflow as it is capped with underlying asset total supply
      totalAssetsAfter = _totalAssets + assets;
    }
    if (totalAssetsAfter > capacity()) revert Errors.CapacityExceeded();

    // calculate amount of shares to mint
    shares = _convertToShares(assets, Math.Rounding.Ceil);

    // update state
    _totalAssets = SafeCast.toUint128(totalAssetsAfter);
    _mintShares(to, shares);

    emit Deposited(msg.sender, to, assets, shares, referrer);
  }

  /**
   * @dev Internal function for sending user shares to the exit queue
   * @param user The address of the user
   * @param shares The number of shares to lock
   * @param receiver The address that will receive assets upon withdrawal
   * @return positionTicket The position ticket of the exit queue
   */
  function _enterExitQueue(
    address user,
    uint256 shares,
    address receiver
  ) internal returns (uint256 positionTicket) {
    _checkHarvested();
    if (shares == 0) revert Errors.InvalidShares();
    if (receiver == address(0)) revert Errors.ZeroAddress();

    // calculate amount of assets to lock
    uint256 assets = convertToAssets(shares);
    if (assets == 0) revert Errors.InvalidAssets();

    // convert assets to exiting tickets
    uint256 exitingTickets = _convertAssetsToExitTickets(assets);

    // reduce total assets
    _totalAssets -= SafeCast.toUint128(assets);

    // burn shares
    _burnShares(user, shares);

    // SLOAD to memory
    uint256 totalExitingTickets = _totalExitingTickets;

    // calculate position ticket
    positionTicket = _totalExitedTickets + totalExitingTickets;

    // increase total exiting assets and tickets
    totalExitingAssets += SafeCast.toUint128(assets);
    _totalExitingTickets = SafeCast.toUint128(totalExitingTickets + exitingTickets);

    // add to the exit requests
    _exitRequests[
      keccak256(abi.encode(receiver, block.timestamp, positionTicket))
    ] = exitingTickets;

    emit ExitQueueEntered(user, receiver, positionTicket, assets);
  }

  /**
   * @dev Internal function for calculating the number of assets that can be withdrawn
   * @return assets The number of assets that can be withdrawn
   */
  function _getTotalExitableTickets() private view returns (uint256) {
    // calculate available assets
    uint256 availableAssets = _vaultAssets() - _unclaimedAssets;
    uint256 queuedAssets = convertToAssets(_queuedShares);
    if (queuedAssets > 0) {
      unchecked {
        // cannot underflow as availableAssets >= queuedV1Assets
        availableAssets = availableAssets > queuedAssets ? availableAssets - queuedAssets : 0;
      }
    }
    if (availableAssets == 0) return 0;

    // calculate number of tickets that can be withdrawn based on available assets
    return _convertAssetsToExitTickets(Math.min(availableAssets, totalExitingAssets));
  }

  /**
   * @dev Internal function for transferring assets from the Vault to the receiver
   * @dev IMPORTANT: because control is transferred to the receiver, care must be
   *    taken to not create reentrancy vulnerabilities. The Vault must follow the checks-effects-interactions pattern:
   *    https://docs.soliditylang.org/en/v0.8.22/security-considerations.html#use-the-checks-effects-interactions-pattern
   * @param receiver The address that will receive the assets
   * @param assets The number of assets to transfer
   */
  function _transferVaultAssets(address receiver, uint256 assets) internal virtual;

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
