// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {IVaultsRegistry} from '../interfaces/IVaultsRegistry.sol';
import {EthVaultFactory} from '../vaults/ethereum/EthVaultFactory.sol';

contract EthVaultFactoryMock is EthVaultFactory {
  constructor(
    address _publicVaultImpl,
    IVaultsRegistry vaultsRegistry
  ) EthVaultFactory(_publicVaultImpl, vaultsRegistry) {}

  function getGasCostOfComputeAddresses(address deployer) external view returns (uint256) {
    uint256 gasBefore = gasleft();
    computeAddresses(deployer);
    return gasBefore - gasleft();
  }
}
