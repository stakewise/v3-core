// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {EthPrivateVault} from '../vaults/ethereum/EthPrivateVault.sol';

contract EthPrivateVaultV2Mock is EthPrivateVault {
  uint128 public newVar;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address _keeper,
    address _vaultsRegistry,
    address _validatorsRegistry,
    address osToken,
    address osTokenConfig,
    address sharedMevEscrow
  )
    EthPrivateVault(
      _keeper,
      _vaultsRegistry,
      _validatorsRegistry,
      osToken,
      osTokenConfig,
      sharedMevEscrow
    )
  {}

  function initialize(bytes calldata data) external payable virtual override reinitializer(2) {
    (newVar) = abi.decode(data, (uint128));
  }

  function somethingNew() external pure returns (bool) {
    return true;
  }

  function version() public pure virtual override returns (uint8) {
    return 2;
  }
}