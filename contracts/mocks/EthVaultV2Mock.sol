// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {IEthValidatorsRegistry} from '../interfaces/IEthValidatorsRegistry.sol';
import {IVaultsRegistry} from '../interfaces/IVaultsRegistry.sol';
import {EthVault} from '../vaults/ethereum/EthVault.sol';

contract EthVaultV2Mock is EthVault {
  uint128 public newVar;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address _keeper,
    address _vaultsRegistry,
    address _validatorsRegistry
  ) EthVault(_keeper, _vaultsRegistry, _validatorsRegistry) {}

  function initialize(bytes calldata data) external override reinitializer(2) {
    (newVar) = abi.decode(data, (uint128));
  }

  function somethingNew() external pure returns (bool) {
    return true;
  }
}
