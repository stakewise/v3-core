// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {EthVaultV5Mock} from './EthVaultV5Mock.sol';

contract EthVaultV6Mock is EthVaultV5Mock {
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
    EthVaultV5Mock(
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

  function initialize(bytes calldata data) external payable override reinitializer(6) {}

  function version() public pure virtual override returns (uint8) {
    return 6;
  }
}
