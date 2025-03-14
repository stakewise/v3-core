// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {EthPrivVault} from '../vaults/ethereum/EthPrivVault.sol';

contract EthPrivVaultV4Mock is EthPrivVault {
  uint128 public newVar;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address keeper,
    address vaultsRegistry,
    address validatorsRegistry,
    address validatorsWithdrawals,
    address validatorsConsolidations,
    address consolidationsChecker,
    address osTokenVaultController,
    address osTokenConfig,
    address osTokenVaultEscrow,
    address sharedMevEscrow,
    address depositDataRegistry,
    uint256 exitingAssetsClaimDelay
  )
    EthPrivVault(
      keeper,
      vaultsRegistry,
      validatorsRegistry,
      validatorsWithdrawals,
      validatorsConsolidations,
      consolidationsChecker,
      osTokenVaultController,
      osTokenConfig,
      osTokenVaultEscrow,
      sharedMevEscrow,
      depositDataRegistry,
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
