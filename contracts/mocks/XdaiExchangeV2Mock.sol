// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {XdaiExchange} from '../misc/XdaiExchange.sol';

contract XdaiExchangeV2Mock is XdaiExchange {
  uint256 public newVar;

  constructor(
    address gnoToken,
    bytes32 balancerPoolId,
    address balancerVault,
    address vaultsRegistry,
    address daiPriceFeed,
    address gnoPriceFeed
  )
    XdaiExchange(
      gnoToken,
      balancerPoolId,
      balancerVault,
      vaultsRegistry,
      daiPriceFeed,
      gnoPriceFeed
    )
  {}

  function initializeV2(address initialOwner) external reinitializer(2) {}
}
