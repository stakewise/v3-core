// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {EigenPodOwner} from '../vaults/ethereum/restake/EigenPodOwner.sol';

contract EigenPodOwnerV2Mock is EigenPodOwner {
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address eigenPodManager,
    address eigenDelegationManager,
    address eigenDelayedWithdrawalRouter
  ) EigenPodOwner(eigenPodManager, eigenDelegationManager, eigenDelayedWithdrawalRouter) {}

  function initialize(bytes calldata data) external virtual override reinitializer(2) {}

  function somethingNew() external pure returns (bool) {
    return true;
  }
}
