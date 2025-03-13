// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {IEthValidatorsRegistry} from '../interfaces/IEthValidatorsRegistry.sol';
import {IVaultsRegistry} from '../interfaces/IVaultsRegistry.sol';
import {EthVault} from '../vaults/ethereum/EthVault.sol';
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
  constructor(
    address _keeper,
    address _vaultsRegistry,
    address _validatorsRegistry,
    address _validatorsWithdrawals,
    address _validatorsConsolidations,
    address _consolidationsChecker,
    address osTokenVaultController,
    address osTokenConfig,
    address osTokenVaultEscrow,
    address sharedMevEscrow,
    uint256 exitingAssetsClaimDelay
  )
    EthVault(
      _keeper,
      _vaultsRegistry,
      _validatorsRegistry,
      _validatorsWithdrawals,
      _validatorsConsolidations,
      _consolidationsChecker,
      osTokenVaultController,
      osTokenConfig,
      osTokenVaultEscrow,
      sharedMevEscrow,
      exitingAssetsClaimDelay
    )
  {}

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
