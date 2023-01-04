// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {IRegistry} from '../interfaces/IRegistry.sol';
import {EthVaultFactory} from '../vaults/ethereum/EthVaultFactory.sol';

contract EthVaultFactoryMock is EthVaultFactory {
  constructor(
    address _publicVaultImpl,
    IRegistry registry
  ) EthVaultFactory(_publicVaultImpl, registry) {}

  function getGasCostOfComputeAddresses(address deployer) external view returns (uint256) {
    uint256 gasBefore = gasleft();
    computeAddresses(deployer);
    return gasBefore - gasleft();
  }
}
