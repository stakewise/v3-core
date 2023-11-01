// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {Clones} from '@openzeppelin/contracts/proxy/Clones.sol';
import {IRewardSplitter} from '../interfaces/IRewardSplitter.sol';
import {IRewardSplitterFactory} from '../interfaces/IRewardSplitterFactory.sol';

/**
 * @title RewardSplitterFactory
 * @author StakeWise
 * @notice Factory for deploying the RewardSplitter contract
 */
contract RewardSplitterFactory is IRewardSplitterFactory {
  /// @inheritdoc IRewardSplitterFactory
  address public immutable override implementation;

  /**
   * @dev Constructor
   * @param _implementation The implementation address of RewardSplitter
   */
  constructor(address _implementation) {
    implementation = _implementation;
  }

  /// @inheritdoc IRewardSplitterFactory
  function createRewardSplitter(address vault) external override returns (address rewardSplitter) {
    // deploy and initialize reward splitter
    rewardSplitter = Clones.clone(implementation);
    IRewardSplitter(rewardSplitter).initialize(msg.sender, vault);

    // emit event
    emit RewardSplitterCreated(msg.sender, vault, rewardSplitter);
  }
}
