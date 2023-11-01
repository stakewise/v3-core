// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {IOsTokenVaultController} from '../interfaces/IOsTokenVaultController.sol';

contract UnknownVaultMock {
  IOsTokenVaultController private immutable _osTokenVaultController;
  address private immutable _implementation;

  constructor(IOsTokenVaultController osTokenVaultController, address implementation_) {
    _osTokenVaultController = osTokenVaultController;
    _implementation = implementation_;
  }

  function mintOsToken(address account, uint256 amount) external {
    _osTokenVaultController.mintShares(account, amount);
  }

  function burnOsToken(uint256 amount) external {
    _osTokenVaultController.burnShares(msg.sender, amount);
  }

  function implementation() external view returns (address) {
    return _implementation;
  }
}
