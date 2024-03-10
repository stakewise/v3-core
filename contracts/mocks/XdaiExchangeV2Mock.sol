// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {XdaiExchange} from '../misc/XdaiExchange.sol';

contract XdaiExchangeV2Mock is XdaiExchange {
  uint256 public newVar;

  constructor(
    address gnoToken,
    bytes32 balancerPoolId,
    address balancerVault,
    address vaultsRegistry
  ) XdaiExchange(gnoToken, balancerPoolId, balancerVault, vaultsRegistry) {}

  function initializeV2(address initialOwner) external reinitializer(2) {}

  // invalid swap function
  function swap(uint256 limit, uint256) external payable override returns (uint256 assets) {
    return limit;
  }
}
