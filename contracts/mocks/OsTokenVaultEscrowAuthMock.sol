// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IOsTokenVaultEscrowAuth} from '../interfaces/IOsTokenVaultEscrowAuth.sol';

/**
 * @title OsTokenVaultEscrowAuthMock
 * @author StakeWise
 * @notice Mocks the OsTokenVaultEscrowAuth contract for testing purposes
 */
contract OsTokenVaultEscrowAuthMock is Ownable, IOsTokenVaultEscrowAuth {
  mapping(address => bool) public _canRegister;

  constructor(address _owner) Ownable(_owner) {}

  function setCanRegister(address user, bool canRegister_) external onlyOwner {
    _canRegister[user] = canRegister_;
  }

  /// @inheritdoc IOsTokenVaultEscrowAuth
  function canRegister(
    address,
    address owner,
    uint256,
    uint256
  ) external view override returns (bool) {
    return _canRegister[owner];
  }
}
