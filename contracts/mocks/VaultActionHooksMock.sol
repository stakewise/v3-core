// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IVaultActionHooks} from '../interfaces/IVaultActionHooks.sol';

contract VaultActionHooksMock is IVaultActionHooks {
  event UserBalanceChange(address caller, address user, uint256 newBalance);

  function onUserBalanceChange(address caller, address user, uint256 newBalance) external override {
    emit UserBalanceChange(caller, user, newBalance);
  }
}
