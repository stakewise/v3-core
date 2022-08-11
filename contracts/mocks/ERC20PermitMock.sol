// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.15;

import {ERC20Permit} from '../base/ERC20Permit.sol';
import {IERC20} from '../interfaces/IERC20.sol';

/**
 * @title ERC20PermitMock
 * @dev ERC20Permit with minting logic
 */
contract ERC20PermitMock is ERC20Permit {
  uint256 private _totalSupply;

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

  /// @inheritdoc IERC20
  function totalSupply() external view override returns (uint256) {
    return _totalSupply;
  }

  function _mint(address to, uint256 amount) internal {
    _totalSupply += amount;

    // Cannot overflow because the sum of all user
    // balances can't exceed the max uint256 value
    unchecked {
      balanceOf[to] += amount;
    }

    emit Transfer(address(0), to, amount);
  }
}
