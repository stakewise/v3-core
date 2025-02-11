// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {IKeeperRewards} from '../interfaces/IKeeperRewards.sol';
import {IRewardSplitter} from '../interfaces/IRewardSplitter.sol';
import {IVaultState} from '../interfaces/IVaultState.sol';
import {IVaultEnterExit} from '../interfaces/IVaultEnterExit.sol';
import {IVaultAdmin} from '../interfaces/IVaultAdmin.sol';
import {Multicall} from '../base/Multicall.sol';
import {Errors} from '../libraries/Errors.sol';

/**
 * @title RewardSplitter
 * @author StakeWise
 * @notice The RewardSplitter can be used to split the rewards of the fee recipient of the vault based on configures shares
 */
contract RewardSplitter is IRewardSplitter, Initializable, Multicall {
  uint256 private constant _wad = 1e18;

  /// @inheritdoc IRewardSplitter
  address public override vault;

  /// @inheritdoc IRewardSplitter
  uint256 public override totalShares;

  /// @inheritdoc IRewardSplitter
  bool public isClaimOnBehalfEnabled;

  mapping(address => ShareHolder) private _shareHolders;
  mapping(address => uint256) private _unclaimedRewards;
  mapping(uint256 positionTicket => address onBehalf) public _exitPositions;

  uint128 private _totalRewards;
  uint128 private _rewardPerShare;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @inheritdoc IRewardSplitter
  function initialize(address _vault) external override initializer {
    vault = _vault;
  }

  /// @inheritdoc IRewardSplitter
  function setClaimOnBehalf(bool enabled) external {
    if (msg.sender != IVaultAdmin(vault).admin()) revert Errors.AccessDenied();
    isClaimOnBehalfEnabled = enabled;
    emit ClaimOnBehalfUpdated(enabled);
  }

  /// @inheritdoc IRewardSplitter
  function totalRewards() external view override returns (uint128) {
    return _totalRewards;
  }

  /// @inheritdoc IRewardSplitter
  function sharesOf(address account) external view override returns (uint256) {
    return _shareHolders[account].shares;
  }

  /// @inheritdoc IRewardSplitter
  function rewardsOf(address account) public view override returns (uint256) {
    // SLOAD to memory
    ShareHolder memory shareHolder = _shareHolders[account];
    // calculate period rewards based on current reward per share
    uint256 periodRewards = Math.mulDiv(
      shareHolder.shares,
      _rewardPerShare - shareHolder.rewardPerShare,
      _wad
    );
    return _unclaimedRewards[account] + periodRewards;
  }

  /// @inheritdoc IRewardSplitter
  function canSyncRewards() external view override returns (bool) {
    return totalShares > 0 && _totalRewards != IVaultState(vault).getShares(address(this));
  }

  /// @inheritdoc IRewardSplitter
  function increaseShares(address account, uint128 amount) external override {
    if (msg.sender != IVaultAdmin(vault).admin()) revert Errors.AccessDenied();
    if (account == address(0)) revert InvalidAccount();
    if (amount == 0) revert InvalidAmount();

    // update rewards state
    syncRewards();

    // update unclaimed rewards
    _unclaimedRewards[account] = rewardsOf(account);

    // increase shares for the account
    _shareHolders[account] = ShareHolder({
      shares: _shareHolders[account].shares + amount,
      rewardPerShare: _rewardPerShare
    });
    totalShares += amount;

    // emit event
    emit SharesIncreased(account, amount);
  }

  /// @inheritdoc IRewardSplitter
  function decreaseShares(address account, uint128 amount) external override {
    if (msg.sender != IVaultAdmin(vault).admin()) revert Errors.AccessDenied();
    if (account == address(0)) revert InvalidAccount();
    if (amount == 0) revert InvalidAmount();

    // update rewards state
    syncRewards();

    // update unclaimed rewards
    _unclaimedRewards[account] = rewardsOf(account);

    // decrease shares for the account
    _shareHolders[account] = ShareHolder({
      shares: _shareHolders[account].shares - amount,
      rewardPerShare: _rewardPerShare
    });
    totalShares -= amount;

    // emit event
    emit SharesDecreased(account, amount);
  }

  /// @inheritdoc IRewardSplitter
  function updateVaultState(IKeeperRewards.HarvestParams calldata harvestParams) external override {
    IVaultState(vault).updateState(harvestParams);
  }

  /// @inheritdoc IRewardSplitter
  function claimVaultTokens(uint256 rewards, address receiver) external override {
    if (rewards == type(uint256).max) {
      rewards = rewardsOf(msg.sender);
    }
    _withdrawRewards(msg.sender, rewards);
    // NB! will revert if vault is not ERC-20
    SafeERC20.safeTransfer(IERC20(vault), receiver, rewards);
  }

  /// @inheritdoc IRewardSplitter
  function enterExitQueue(
    uint256 rewards,
    address receiver
  ) external override returns (uint256 positionTicket) {
    if (rewards == type(uint256).max) {
      rewards = rewardsOf(msg.sender);
    }
    _withdrawRewards(msg.sender, rewards);
    return IVaultEnterExit(vault).enterExitQueue(rewards, receiver);
  }

  function enterExitQueueOnBehalf(uint256 rewards, address onBehalf) external {
    if (!isClaimOnBehalfEnabled) return;

    if (rewards == type(uint256).max) {
      rewards = rewardsOf(onBehalf);
    }
    _withdrawRewards(onBehalf, rewards);
    uint256 positionTicket = IVaultEnterExit(vault).enterExitQueue(rewards, address(this));
    _exitPositions[positionTicket] = onBehalf;
  }

  function claimExitedAssetsOnBehalf(
    uint256 positionTicket,
    uint256 timestamp,
    uint256 exitQueueIndex
  ) external {
    if (!isClaimOnBehalfEnabled) revert Errors.AccessDenied();
    address onBehalf = _exitPositions[positionTicket];
    if (onBehalf == address(0)) revert Errors.AccessDenied();

    // calculate exited tickets and assets
    (uint256 leftTickets, , uint256 exitedAssets) = IVaultEnterExit(vault).calculateExitedAssets(
      address(this),
      positionTicket,
      timestamp,
      exitQueueIndex
    );
    // disallow partial claims (1 ticket could be a rounding error)
    if (leftTickets > 1) revert Errors.AccessDenied();

    IVaultEnterExit(vault).claimExitedAssets(positionTicket, timestamp, exitQueueIndex);
    _exitPositions[positionTicket] = address(0);

    Address.sendValue(payable(onBehalf), exitedAssets);
  }

  /// @inheritdoc IRewardSplitter
  function syncRewards() public override {
    // SLOAD to memory
    uint256 _totalShares = totalShares;
    if (_totalShares == 0) return;

    address _vault = vault;
    // vault state must be up-to-date
    if (IVaultState(_vault).isStateUpdateRequired()) revert NotHarvested();

    // SLOAD to memory
    uint256 prevTotalRewards = _totalRewards;

    // retrieve new total rewards
    // NB! make sure vault has getShares function to retrieve number of shares assigned
    uint256 newTotalRewards = IVaultState(_vault).getShares(address(this));
    if (newTotalRewards == prevTotalRewards) return;

    // calculate new cumulative reward per share
    // reverts when total shares is zero
    uint256 newRewardPerShare = _rewardPerShare +
      Math.mulDiv(newTotalRewards - prevTotalRewards, _wad, _totalShares);

    // update state
    _totalRewards = SafeCast.toUint128(newTotalRewards);
    _rewardPerShare = SafeCast.toUint128(newRewardPerShare);

    // emit event
    emit RewardsSynced(newTotalRewards, newRewardPerShare);
  }

  function _withdrawRewards(address account, uint256 rewards) private {
    // Sync rewards from the vault
    syncRewards();

    // get user total number of rewards
    uint256 accountRewards = rewardsOf(account);

    // withdraw shareholder rewards from the splitter
    _totalRewards -= SafeCast.toUint128(rewards);

    // update shareholder
    // reverts if withdrawn rewards exceed total
    _unclaimedRewards[account] = accountRewards - rewards;
    _shareHolders[account].rewardPerShare = _rewardPerShare;

    // emit event
    emit RewardsWithdrawn(account, rewards);
  }
}
