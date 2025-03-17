// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IEthVault} from '../interfaces/IEthVault.sol';
import {EthVaultV5Mock} from './EthVaultV5Mock.sol';

contract EthVaultV6Mock is EthVaultV5Mock {
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(IEthVault.EthVaultConstructorArgs memory args) EthVaultV5Mock(args) {}

  function initialize(bytes calldata data) external payable override reinitializer(6) {}

  function version() public pure virtual override returns (uint8) {
    return 6;
  }
}
