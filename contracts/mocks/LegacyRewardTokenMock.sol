// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.22;

import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {IEthGenesisVault} from '../interfaces/IEthGenesisVault.sol';

contract LegacyRewardTokenMock {
  address public vault;
  uint256 public totalStaked;
  uint256 public totalRewards;
  uint256 public totalPenalty;

  function setVault(address _vault) external {
    vault = _vault;
  }

  function totalAssets() public view returns (uint256) {
    return totalStaked + totalRewards;
  }

  function setTotalStaked(uint256 _totalStaked) external {
    totalStaked = _totalStaked;
  }

  function setTotalPenalty(uint256 _totalPenalty) external {
    totalPenalty = _totalPenalty;
  }

  function setTotalRewards(uint256 _totalRewards) external {
    totalRewards = _totalRewards;
  }

  function updateTotalRewards(int256 rewardsDelta) external {
    if (rewardsDelta > 0) {
      totalRewards += uint256(rewardsDelta);
    } else {
      totalPenalty += uint256(-rewardsDelta);
    }
  }

  function migrate(address receiver, uint256 principal, uint256 reward) external {
    uint256 assets = principal + reward;

    uint256 _totalPenalty = totalPenalty; // gas savings
    if (_totalPenalty > 0) {
      uint256 _totalAssets = totalAssets(); // gas savings
      // apply penalty to assets
      uint256 assetsAfterPenalty = Math.mulDiv(assets, _totalAssets - _totalPenalty, _totalAssets);
      totalPenalty = _totalPenalty + assetsAfterPenalty - assets;
      assets = assetsAfterPenalty;
    }
    IEthGenesisVault(vault).migrate(receiver, assets);
  }
}
