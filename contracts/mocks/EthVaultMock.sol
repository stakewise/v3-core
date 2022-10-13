// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {EthVault} from '../vaults/EthVault.sol';
import {ExitQueue} from '../libraries/ExitQueue.sol';
import {IFeesEscrow} from '../interfaces/IFeesEscrow.sol';
import {IEthValidatorsRegistry} from '../interfaces/IEthValidatorsRegistry.sol';
import {IRegistry} from '../interfaces/IRegistry.sol';
import {EthFeesEscrow} from '../vaults/EthFeesEscrow.sol';

/**
 * @title EthVaultMock
 * @author StakeWise
 * @notice Adds mocked functions to the EthVault contract
 */
contract EthVaultMock is EthVault {
  using SafeCast for uint256;
  using ExitQueue for ExitQueue.History;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address _keeper,
    IRegistry _registry,
    IEthValidatorsRegistry _validatorsRegistry
  ) EthVault(_keeper, _registry, _validatorsRegistry) {}

  function mockMint(address receiver, uint256 assets) external returns (uint256 shares) {
    // calculate amount of shares to mint
    shares = convertToShares(assets);

    // update counters
    _totalShares += SafeCast.toUint128(shares);

    unchecked {
      // Cannot overflow because the sum of all user
      // balances can't exceed the max uint256 value
      balanceOf[receiver] += shares;
    }

    emit Transfer(address(0), receiver, shares);
    emit Deposit(msg.sender, receiver, assets, shares);
  }

  function getGasCostOfGetCheckpointIndex(uint256 exitQueueId) external view returns (uint256) {
    uint256 gasBefore = gasleft();
    _exitQueue.getCheckpointIndex(exitQueueId);
    return gasBefore - gasleft();
  }

  function _setTotalAssets(uint128 value) external {
    _totalAssets = value;
  }
}
