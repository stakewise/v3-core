// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {IKeeperRewards} from '../interfaces/IKeeperRewards.sol';
import {IRewardSplitter} from '../interfaces/IRewardSplitter.sol';
import {IVaultState} from '../interfaces/IVaultState.sol';
import {IVaultToken} from '../interfaces/IVaultToken.sol';
import {IVaultEnterExit} from '../interfaces/IVaultEnterExit.sol';
import {Multicall} from '../base/Multicall.sol';

/**
 * @title RewardSplitter
 * @author StakeWise
 * @notice The RewardSplitter can be used to split the rewards of the fee recipient of the vault based on configures shares
 */
contract RewardSplitter is IRewardSplitter, Initializable, OwnableUpgradeable, Multicall {
  uint256 private constant _wad = 1e18;

  /// @inheritdoc IRewardSplitter
  address public override vault;

  /// @inheritdoc IRewardSplitter
  uint256 public override totalShares;

  mapping(address => ShareHolder) private _shareHolders;
  mapping(address => uint256) private _unclaimedRewards;

  uint128 private _totalRewards;
  uint128 private _rewardPerShare;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @inheritdoc IRewardSplitter
  function initialize(address owner, address _vault) external override initializer {
    _transferOwnership(owner);
    vault = _vault;
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
    return totalShares > 0 && _totalRewards != IVaultToken(vault).balanceOf(address(this));
  }

  /// @inheritdoc IRewardSplitter
  function increaseShares(address account, uint128 amount) external override onlyOwner {
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
  function decreaseShares(address account, uint128 amount) external override onlyOwner {
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
    _withdrawRewards(msg.sender, rewards);
    // NB! will revert if vault is not ERC-20
    IVaultToken(vault).transfer(receiver, rewards);
  }

  /// @inheritdoc IRewardSplitter
  function enterExitQueue(
    uint256 rewards,
    address receiver
  ) external override returns (uint256 positionTicket) {
    _withdrawRewards(msg.sender, rewards);
    return IVaultEnterExit(vault).enterExitQueue(rewards, receiver);
  }

  /// @inheritdoc IRewardSplitter
  function redeem(uint256 rewards, address receiver) external override returns (uint256 assets) {
    _withdrawRewards(msg.sender, rewards);
    return IVaultEnterExit(vault).redeem(rewards, receiver);
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
    // NB! make sure vault has balanceOf function to retrieve number of shares assigned
    uint256 newTotalRewards = IVaultToken(_vault).balanceOf(address(this));
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
    // get user total number of rewards
    uint256 accountRewards = rewardsOf(account);

    // update state
    _totalRewards -= SafeCast.toUint128(rewards);
    // reverts if withdrawn rewards exceed total
    _unclaimedRewards[account] = accountRewards - rewards;
    _shareHolders[account].rewardPerShare = _rewardPerShare;

    // emit event
    emit RewardsWithdrawn(account, rewards);
  }
}
