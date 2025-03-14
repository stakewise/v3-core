// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {EthVaultV5Mock} from './EthVaultV5Mock.sol';

contract EthVaultV6Mock is EthVaultV5Mock {
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address keeper,
    address vaultsRegistry,
    address validatorsRegistry,
    address validatorsWithdrawals,
    address validatorsConsolidations,
    address consolidationsChecker,
    address osTokenVaultController,
    address osTokenConfig,
    address osTokenVaultEscrow,
    address sharedMevEscrow,
    address depositDataRegistry,
    uint256 exitingAssetsClaimDelay
  )
    EthVaultV5Mock(
      keeper,
      vaultsRegistry,
      validatorsRegistry,
      validatorsWithdrawals,
      validatorsConsolidations,
      consolidationsChecker,
      osTokenVaultController,
      osTokenConfig,
      osTokenVaultEscrow,
      sharedMevEscrow,
      depositDataRegistry,
      exitingAssetsClaimDelay
    )
  {}

  function initialize(bytes calldata data) external payable override reinitializer(6) {}

  function version() public pure virtual override returns (uint8) {
    return 6;
  }
}
