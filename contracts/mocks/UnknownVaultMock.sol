// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {IOsToken} from '../interfaces/IOsToken.sol';

contract UnknownVaultMock {
  IOsToken private immutable _osToken;
  address private immutable _implementation;

  constructor(IOsToken osToken, address implementation_) {
    _osToken = osToken;
    _implementation = implementation_;
  }

  function mintOsToken(address account, uint256 amount) external {
    _osToken.mintShares(account, amount);
  }

  function burnOsToken(uint256 amount) external {
    _osToken.burnShares(msg.sender, amount);
  }

  function implementation() external view returns (address) {
    return _implementation;
  }
}
