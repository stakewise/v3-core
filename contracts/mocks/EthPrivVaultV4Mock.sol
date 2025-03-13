// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {EthPrivVault} from '../vaults/ethereum/EthPrivVault.sol';

contract EthPrivVaultV4Mock is EthPrivVault {
  uint128 public newVar;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address _keeper,
    address _vaultsRegistry,
    address _validatorsRegistry,
    address _validatorsWithdrawals,
    address _validatorsConsolidations,
    address _consolidationsChecker,
    address osTokenVaultController,
    address osTokenConfig,
    address osTokenVaultEscrow,
    address sharedMevEscrow,
    uint256 exitingAssetsClaimDelay
  )
    EthPrivVault(
      _keeper,
      _vaultsRegistry,
      _validatorsRegistry,
      _validatorsWithdrawals,
      _validatorsConsolidations,
      _consolidationsChecker,
      osTokenVaultController,
      osTokenConfig,
      osTokenVaultEscrow,
      sharedMevEscrow,
      exitingAssetsClaimDelay
    )
  {}

  function initialize(bytes calldata data) external payable virtual override reinitializer(4) {
    (newVar) = abi.decode(data, (uint128));
  }

  function somethingNew() external pure returns (bool) {
    return true;
  }

  function version() public pure virtual override returns (uint8) {
    return 4;
  }
}
