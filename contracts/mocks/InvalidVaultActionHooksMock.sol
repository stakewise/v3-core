// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IVaultActionHooks} from '../interfaces/IVaultActionHooks.sol';

contract InvalidVaultActionHooksMock is IVaultActionHooks {
  error CallFailed();

  function onUserBalanceChange(address, address, uint256) external pure override {
    revert CallFailed();
  }
}
