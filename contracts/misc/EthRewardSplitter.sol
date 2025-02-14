// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {RewardSplitter} from './RewardSplitter.sol';
import {IRewardSplitter} from '../interfaces/IRewardSplitter.sol';

/**
 * @title EthRewardSplitter
 * @author StakeWise
 * @notice The EthRewardSplitter can be used on Ethereum networks 
 to split the rewards of the fee recipient of the vault based on configured shares
 */
contract EthRewardSplitter is ReentrancyGuard, RewardSplitter {
  constructor() RewardSplitter() {}

  /// Allows to claim rewards from the vault and receive them to the reward splitter address
  receive() external payable {}

  /// @inheritdoc RewardSplitter
  function claimExitedAssetsOnBehalf(
    uint256 positionTicket,
    uint256 timestamp,
    uint256 exitQueueIndex
  ) public override nonReentrant {
    super.claimExitedAssetsOnBehalf(positionTicket, timestamp, exitQueueIndex);
  }

  /// @inheritdoc RewardSplitter
  function _transferRewards(address shareholder, uint256 amount) internal override {
    Address.sendValue(payable(shareholder), amount);
  }
}
