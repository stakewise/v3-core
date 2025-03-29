// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IEthVault} from '../interfaces/IEthVault.sol';
import {EthPrivVault} from '../vaults/ethereum/EthPrivVault.sol';

contract EthPrivVaultV6Mock is EthPrivVault {
  uint128 public newVar;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(IEthVault.EthVaultConstructorArgs memory args) EthPrivVault(args) {}

  function initialize(bytes calldata data) external payable virtual override reinitializer(6) {
    (newVar) = abi.decode(data, (uint128));
  }

  function somethingNew() external pure returns (bool) {
    return true;
  }

  function version() public pure virtual override returns (uint8) {
    return 6;
  }
}
