// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {EthVault, IEthVault} from '../vaults/ethereum/EthVault.sol';
import {ExitQueue} from '../libraries/ExitQueue.sol';

/**
 * @title EthVaultMock
 * @author StakeWise
 * @notice Adds mocked functions to the EthVault contract
 */
contract EthVaultMock is EthVault {
  using ExitQueue for ExitQueue.History;

  uint256 private constant _securityDeposit = 1e9;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(IEthVault.EthVaultConstructorArgs memory args) EthVault(args) {}

  function getGasCostOfGetExitQueueIndex(uint256 positionTicket) external view returns (uint256) {
    uint256 gasBefore = gasleft();
    _exitQueue.getCheckpointIndex(positionTicket);
    return gasBefore - gasleft();
  }

  function _setTotalAssets(uint128 value) external {
    _totalAssets = value;
  }

  function _setTotalShares(uint128 value) external {
    _totalShares = value;
  }

  function resetSecurityDeposit() external {
    _balances[address(this)] -= _securityDeposit;
    _totalShares -= SafeCast.toUint128(_securityDeposit);
    _totalAssets -= SafeCast.toUint128(_securityDeposit);
    _transferVaultAssets(address(0), _securityDeposit);
  }
}
