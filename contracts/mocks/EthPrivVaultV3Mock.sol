// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {EthPrivVault} from '../vaults/ethereum/EthPrivVault.sol';

contract EthPrivVaultV3Mock is EthPrivVault {
  uint128 public newVar;

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
    EthPrivVault(
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

  function initialize(bytes calldata data) external payable virtual override reinitializer(3) {
    (newVar) = abi.decode(data, (uint128));
  }

  function somethingNew() external pure returns (bool) {
    return true;
  }

  function version() public pure virtual override returns (uint8) {
    return 3;
  }
}
