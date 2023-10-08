// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {EthVaultV2Mock} from './EthVaultV2Mock.sol';

contract EthVaultV3Mock is EthVaultV2Mock {
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address _keeper,
    address _vaultsRegistry,
    address _validatorsRegistry,
    address osToken,
    address osTokenConfig,
    address sharedMevEscrow,
    uint256 exitingAssetsClaimDelay
  )
    EthVaultV2Mock(
      _keeper,
      _vaultsRegistry,
      _validatorsRegistry,
      osToken,
      osTokenConfig,
      sharedMevEscrow,
      exitingAssetsClaimDelay
    )
  {}

  function initialize(bytes calldata data) external payable override reinitializer(3) {}

  function version() public pure virtual override returns (uint8) {
    return 3;
  }
}
