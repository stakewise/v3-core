// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {IKeeperRewards} from '../../interfaces/IKeeperRewards.sol';
import {IVaultEnterExit} from '../../interfaces/IVaultEnterExit.sol';
import {ExitQueue} from '../../libraries/ExitQueue.sol';
import {VaultImmutables} from './VaultImmutables.sol';
import {VaultToken} from './VaultToken.sol';
import {VaultState} from './VaultState.sol';

/**
 * @title VaultEnterExit
 * @author StakeWise
 * @notice Defines the functionality for entering and exiting the Vault
 */
abstract contract VaultEnterExit is VaultImmutables, VaultToken, VaultState, IVaultEnterExit {
  using ExitQueue for ExitQueue.History;

  /// @inheritdoc IVaultEnterExit
  function redeem(
    uint256 shares,
    address receiver,
    address owner
  ) public virtual override returns (uint256 assets) {
    _checkHarvested();
    if (shares == 0) revert InvalidShares();
    if (receiver == address(0)) revert InvalidRecipient();

    // calculate amount of assets to burn
    assets = convertToAssets(shares);

    // reverts in case there are not enough withdrawable assets
    if (assets > withdrawableAssets()) revert InsufficientAssets();

    // reduce allowance
    if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);

    // burn shares
    balanceOf[owner] -= shares;

    // update counters
    unchecked {
      // cannot underflow because the sum of all shares can't exceed the _totalShares
      _totalShares -= SafeCast.toUint128(shares);
      // cannot underflow because the sum of all assets can't exceed the _totalAssets
      _totalAssets -= SafeCast.toUint128(assets);
    }

    // transfer assets to the receiver
    _transferVaultAssets(receiver, assets);

    emit Transfer(owner, address(0), shares);
    emit Redeem(msg.sender, receiver, owner, assets, shares);
  }

  /// @inheritdoc IVaultEnterExit
  function enterExitQueue(
    uint256 shares,
    address receiver,
    address owner
  ) public virtual override returns (uint256 positionCounter) {
    _checkCollateralized();
    if (shares == 0) revert InvalidSharesAmount();
    if (receiver == address(0)) revert InvalidRecipient();

    // SLOAD to memory
    uint256 _queuedShares = queuedShares;

    // calculate position counter
    positionCounter = _exitQueue.getSharesCounter() + _queuedShares;

    // add to the exit requests
    _exitRequests[keccak256(abi.encode(receiver, positionCounter))] = shares;

    // lock tokens in the Vault
    if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);
    // reverts if owner does not have enough shares
    balanceOf[owner] -= shares;

    unchecked {
      // cannot overflow as it is capped with _totalShares
      queuedShares = SafeCast.toUint96(_queuedShares + shares);
    }

    emit Transfer(owner, address(this), shares);
    emit ExitQueueEntered(msg.sender, receiver, owner, positionCounter, shares);
  }

  /// @inheritdoc IVaultEnterExit
  function claimExitedAssets(
    address receiver,
    uint256 positionCounter,
    uint256 checkpointIndex
  )
    external
    override
    returns (uint256 newPositionCounter, uint256 claimedShares, uint256 claimedAssets)
  {
    bytes32 queueId = keccak256(abi.encode(receiver, positionCounter));
    uint256 requestedShares = _exitRequests[queueId];

    // calculate exited shares and assets
    (claimedShares, claimedAssets) = _exitQueue.calculateExitedAssets(
      checkpointIndex,
      positionCounter,
      requestedShares
    );
    // nothing to claim
    if (claimedShares == 0) return (positionCounter, claimedShares, claimedAssets);

    // clean up current exit request
    delete _exitRequests[queueId];

    uint256 leftShares = requestedShares - claimedShares;
    // skip creating new position for the shares rounding error
    if (leftShares > 1) {
      // update user's queue position
      newPositionCounter = positionCounter + claimedShares;
      _exitRequests[keccak256(abi.encode(receiver, newPositionCounter))] = leftShares;
    }

    // transfer assets to the receiver
    _unclaimedAssets -= SafeCast.toUint96(claimedAssets);
    _transferVaultAssets(receiver, claimedAssets);
    emit ExitedAssetsClaimed(
      msg.sender,
      receiver,
      positionCounter,
      newPositionCounter,
      claimedAssets
    );
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
  ) internal returns (uint256 shares) {
    _checkHarvested();
    if (to == address(0)) revert ZeroAddress();
    if (assets == 0) revert InvalidAssets();

    uint256 totalAssetsAfter;
    unchecked {
      // cannot overflow as it is capped with underlying asset total supply
      totalAssetsAfter = _totalAssets + assets;
    }
    if (totalAssetsAfter > capacity()) revert CapacityExceeded();

    // calculate amount of shares to mint
    shares = convertToShares(assets);

    // update counters
    _totalShares += SafeCast.toUint128(shares);
    _totalAssets = SafeCast.toUint128(totalAssetsAfter);

    unchecked {
      // cannot overflow because the sum of all user
      // balances can't exceed the max uint256 value
      balanceOf[to] += shares;
    }

    emit Transfer(address(0), to, shares);
    emit Deposit(msg.sender, to, assets, shares, referrer);
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
