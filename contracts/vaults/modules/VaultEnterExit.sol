// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
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
    uint256 checkpointIdx = _exitQueue.getCheckpointIndex(positionTicket);
    return checkpointIdx < _exitQueue.checkpoints.length ? int256(checkpointIdx) : -1;
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

    // calculate exited tickets and assets
    (exitedTickets, exitedAssets) = _exitQueue.calculateExitedAssets(
      exitQueueIndex,
      positionTicket,
      exitingTickets
    );
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
    if (
      block.timestamp < timestamp + _exitingAssetsClaimDelay ||
      exitedTickets == 0 ||
      exitedAssets == 0
    ) {
      revert Errors.ExitRequestNotProcessed();
    }

    // update unclaimed assets
    _unclaimedAssets -= SafeCast.toUint128(exitedAssets);

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
    emit ExitedAssetsClaimed(msg.sender, positionTicket, newPositionTicket, exitedAssets);
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
   * @param shares The number of shares to send to exit queue
   * @param receiver The address that will receive the assets
   * @return positionTicket The position ticket in the exit queue. Returns max uint256 if no ticket is created.
   */
  function _enterExitQueue(
    address user,
    uint256 shares,
    address receiver
  ) internal virtual returns (uint256 positionTicket) {
    if (shares == 0) revert Errors.InvalidShares();
    if (receiver == address(0)) revert Errors.ZeroAddress();
    if (!_isCollateralized()) {
      // calculate amount of assets to burn
      uint256 assets = convertToAssets(shares);
      if (assets == 0) revert Errors.InvalidAssets();

      // update total assets
      _totalAssets -= SafeCast.toUint128(assets);

      // burn owner shares
      _burnShares(user, shares);

      // transfer assets to the receiver
      _transferVaultAssets(receiver, assets);

      emit Redeemed(user, receiver, assets, shares);

      // no ticket is created, return max value
      return type(uint256).max;
    }

    // SLOAD to memory
    uint256 queuedShares = _queuedShares;

    // calculate position ticket
    positionTicket = _exitQueue.getLatestTotalTickets() + _totalExitingTickets + queuedShares;

    // add to the exit requests
    _exitRequests[keccak256(abi.encode(receiver, block.timestamp, positionTicket))] = shares;

    // reverts if owner does not have enough shares
    _balances[user] -= shares;

    unchecked {
      // cannot overflow as it is capped with _totalShares
      _queuedShares = SafeCast.toUint128(queuedShares + shares);
    }

    emit ExitQueueEntered(user, receiver, positionTicket, shares);
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
