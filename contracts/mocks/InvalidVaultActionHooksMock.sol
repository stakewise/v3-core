// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IVaultActionHooks} from '../interfaces/IVaultActionHooks.sol';

contract InvalidVaultActionHooksMock is IVaultActionHooks {
  error CallFailed();

  function onUserBalanceChange(address caller, address user, uint256 newBalance) external override {
    revert CallFailed();
  }
}
