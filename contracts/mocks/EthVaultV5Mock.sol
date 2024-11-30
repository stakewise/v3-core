// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {EthVaultV4Mock} from './EthVaultV4Mock.sol';

contract EthVaultV5Mock is EthVaultV4Mock {
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address _keeper,
    address _vaultsRegistry,
    address _validatorsRegistry,
    address osTokenVaultController,
    address osTokenConfig,
    address osTokenVaultEscrow,
    address sharedMevEscrow,
    address depositDataRegistry,
    uint256 exitingAssetsClaimDelay
  )
    EthVaultV4Mock(
      _keeper,
      _vaultsRegistry,
      _validatorsRegistry,
      osTokenVaultController,
      osTokenConfig,
      osTokenVaultEscrow,
      sharedMevEscrow,
      depositDataRegistry,
      exitingAssetsClaimDelay
    )
  {}

  function initialize(bytes calldata data) external payable override reinitializer(5) {}

  function version() public pure virtual override returns (uint8) {
    return 5;
  }
}
