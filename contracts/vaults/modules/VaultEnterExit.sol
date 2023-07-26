// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

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

  /// @inheritdoc IVaultEnterExit
  function getExitQueueIndex(uint256 positionTicket) external view override returns (int256) {
    uint256 checkpointIdx = _exitQueue.getCheckpointIndex(positionTicket);
    return checkpointIdx < _exitQueue.checkpoints.length ? int256(checkpointIdx) : -1;
  }

  /// @inheritdoc IVaultEnterExit
  function redeem(
    uint256 shares,
    address receiver
  ) public virtual override returns (uint256 assets) {
    _checkHarvested();
    if (shares == 0) revert Errors.InvalidShares();
    if (receiver == address(0)) revert Errors.ZeroAddress();

    // calculate amount of assets to burn
    assets = convertToAssets(shares);

    // reverts in case there are not enough withdrawable assets
    if (assets > withdrawableAssets()) revert Errors.InsufficientAssets();

    // update total assets
    _totalAssets -= SafeCast.toUint128(assets);

    // burn owner shares
    _burnShares(msg.sender, shares);

    // transfer assets to the receiver
    _transferVaultAssets(receiver, assets);

    emit Redeemed(msg.sender, receiver, assets, shares);
  }

  /// @inheritdoc IVaultEnterExit
  function enterExitQueue(
    uint256 shares,
    address receiver
  ) public virtual override returns (uint256 positionTicket) {
    _checkCollateralized();
    if (shares == 0) revert Errors.InvalidShares();
    if (receiver == address(0)) revert Errors.ZeroAddress();

    // SLOAD to memory
    uint256 _queuedShares = queuedShares;

    // calculate position ticket
    positionTicket = _exitQueue.getLatestTotalTickets() + _queuedShares;

    // add to the exit requests
    _exitRequests[keccak256(abi.encode(receiver, positionTicket))] = shares;

    // reverts if owner does not have enough shares
    _balances[msg.sender] -= shares;

    unchecked {
      // cannot overflow as it is capped with _totalShares
      queuedShares = SafeCast.toUint96(_queuedShares + shares);
    }

    emit ExitQueueEntered(msg.sender, receiver, positionTicket, shares);
  }

  /// @inheritdoc IVaultEnterExit
  function calculateExitedAssets(
    address receiver,
    uint256 positionTicket,
    uint256 exitQueueIndex
  )
    public
    view
    override
    returns (uint256 leftShares, uint256 claimedShares, uint256 claimedAssets)
  {
    uint256 requestedShares = _exitRequests[keccak256(abi.encode(receiver, positionTicket))];

    // calculate exited shares and assets
    (claimedShares, claimedAssets) = _exitQueue.calculateExitedAssets(
      exitQueueIndex,
      positionTicket,
      requestedShares
    );
    leftShares = requestedShares - claimedShares;
  }

  /// @inheritdoc IVaultEnterExit
  function claimExitedAssets(
    uint256 positionTicket,
    uint256 exitQueueIndex
  )
    external
    override
    returns (uint256 newPositionTicket, uint256 claimedShares, uint256 claimedAssets)
  {
    bytes32 queueId = keccak256(abi.encode(msg.sender, positionTicket));

    // calculate exited shares and assets
    uint256 leftShares;
    (leftShares, claimedShares, claimedAssets) = calculateExitedAssets(
      msg.sender,
      positionTicket,
      exitQueueIndex
    );
    // nothing to claim
    if (claimedShares == 0) return (positionTicket, claimedShares, claimedAssets);

    // clean up current exit request
    delete _exitRequests[queueId];

    // skip creating new position for the shares rounding error
    if (leftShares > 1) {
      // update user's queue position
      newPositionTicket = positionTicket + claimedShares;
      _exitRequests[keccak256(abi.encode(msg.sender, newPositionTicket))] = leftShares;
    }

    // transfer assets to the receiver
    _unclaimedAssets -= SafeCast.toUint96(claimedAssets);
    _transferVaultAssets(msg.sender, claimedAssets);
    emit ExitedAssetsClaimed(msg.sender, positionTicket, newPositionTicket, claimedAssets);
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
    shares = _convertToShares(assets, Math.Rounding.Up);

    // update state
    _totalAssets = SafeCast.toUint128(totalAssetsAfter);
    _mintShares(to, shares);

    emit Deposited(msg.sender, to, assets, shares, referrer);
  }

  /**
   * @dev Internal function for transferring assets from the Vault to the receiver
   * @dev IMPORTANT: because control is transferred to the receiver, care must be
   *    taken to not create reentrancy vulnerabilities. The Vault must follow the checks-effects-interactions pattern:
   *    https://docs.soliditylang.org/en/v0.8.20/security-considerations.html#use-the-checks-effects-interactions-pattern
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
