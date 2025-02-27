// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {ReentrancyGuardUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import {RewardSplitter} from './RewardSplitter.sol';
import {IRewardSplitter} from '../interfaces/IRewardSplitter.sol';

/**
 * @title EthRewardSplitter
 * @author StakeWise
 * @notice The EthRewardSplitter can be used on Ethereum networks 
 to split the rewards of the fee recipient of the vault based on configured shares
 */
contract EthRewardSplitter is ReentrancyGuardUpgradeable, RewardSplitter {
  constructor() RewardSplitter() {}

  /// Allows to claim rewards from the vault and receive them to the reward splitter address
  receive() external payable {}

  function initialize(address _vault) external override initializer {
    __ReentrancyGuard_init();
    __RewardSplitter_init(_vault);
  }

  /// @inheritdoc RewardSplitter
  function _transferRewards(address shareholder, uint256 amount) internal override nonReentrant {
    Address.sendValue(payable(shareholder), amount);
  }
}
