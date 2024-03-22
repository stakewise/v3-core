// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {EthVaultV3Mock} from './EthVaultV3Mock.sol';

contract EthVaultV4Mock is EthVaultV3Mock {
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address _keeper,
    address _vaultsRegistry,
    address _validatorsRegistry,
    address osTokenVaultController,
    address osTokenConfig,
    address sharedMevEscrow,
    address depositDataManager,
    uint256 exitingAssetsClaimDelay
  )
    EthVaultV3Mock(
      _keeper,
      _vaultsRegistry,
      _validatorsRegistry,
      osTokenVaultController,
      osTokenConfig,
      sharedMevEscrow,
      depositDataManager,
      exitingAssetsClaimDelay
    )
  {}

  function initialize(bytes calldata data) external payable override reinitializer(4) {}

  function version() public pure virtual override returns (uint8) {
    return 4;
  }
}
