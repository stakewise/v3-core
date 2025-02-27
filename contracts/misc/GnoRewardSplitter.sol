// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {RewardSplitter} from './RewardSplitter.sol';

/**
 * @title GnoRewardSplitter
 * @author StakeWise
 * @notice The GnoRewardSplitter can be used on Gnosis networks 
  to split the rewards of the fee recipient of the vault based on configures shares
 */
contract GnoRewardSplitter is RewardSplitter {
  IERC20 private immutable _gnoToken;

  constructor(address gnoToken) RewardSplitter() {
    _gnoToken = IERC20(gnoToken);
  }

  function initialize(address _vault) external override initializer {
    __RewardSplitter_init(_vault);
  }

  /// @inheritdoc RewardSplitter
  function _transferRewards(address shareholder, uint256 amount) internal override {
    SafeERC20.safeTransfer(_gnoToken, shareholder, amount);
  }
}
