// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {ERC20Permit} from '../base/ERC20Permit.sol';

/**
 * @title ERC20PermitMock
 * @dev ERC20Permit with minting logic
 */
contract ERC20PermitMock is ERC20Permit {
  /**
   * @dev Constructor
   * @param _name The name of the ERC20 token
   * @param _symbol The symbol of the ERC20 token
   */
  constructor(string memory _name, string memory _symbol) ERC20Permit(_name, _symbol) {}

  /**
   * @dev Function to mint tokens to address
   * @param account The account to mint tokens
   * @param value The amount of tokens to mint
   */
  function mint(address account, uint256 value) public {
    _mint(account, value);
  }
}
