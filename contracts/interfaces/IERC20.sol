// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.15;

/**
 * @title ERC20 interface
 * @notice Interface of the ERC20 standard as defined in the EIP.
 **/
interface IERC20 {
  /**
   * @notice Event emitted when tokens are transferred from one address to another, either via `transfer` or `transferFrom`
   * @param from The account from which the tokens were sent, i.e. the balance decreased
   * @param to The account to which the tokens were sent, i.e. the balance increased
   * @param value The amount of tokens that were transferred
   **/
  event Transfer(address indexed from, address indexed to, uint256 value);

  /**
   * @notice Event emitted when the approval amount for the spender of a given owner's tokens changes
   * @param owner The account that approved spending of its tokens
   * @param spender The account for which the spending allowance was modified
   * @param value The new allowance from the owner to the spender
   **/
  event Approval(address indexed owner, address indexed spender, uint256 value);

  /**
   * @notice Function for retrieving name of the token
   * @return The name of the token
   **/
  function name() external view returns (string memory);

  /**
   * @notice Function for retrieving symbol of the token
   * @return The symbol of the token
   **/
  function symbol() external view returns (string memory);

  /**
   * @notice Function for retrieving decimals of the token
   * @return The decimals places of the token
   **/
  function decimals() external view returns (uint8);

  /**
   * @notice Function for retrieving total supply of tokens
   * @return The amount of tokens in existence
   **/
  function totalSupply() external view returns (uint256);

  /**
   * @notice Returns the balance of a token
   * @param account The account for which to look up the number of tokens it has, i.e. its balance
   * @return The number of tokens held by the account
   **/
  function balanceOf(address account) external view returns (uint256);

  /**
   * @notice Transfers the amount of token from the `msg.sender` to the recipient
   * @param to The account that will receive the amount transferred
   * @param amount The number of tokens to send from the sender to the recipient
   * @return Returns true for a successful transfer, false for an unsuccessful transfer
   **/
  function transfer(address to, uint256 amount) external returns (bool);

  /**
   * @notice Returns the current allowance given to a spender by an owner
   * @param owner The account of the token owner
   * @param spender The account of the token spender
   * @return The current allowance granted by `owner` to `spender`
   **/
  function allowance(address owner, address spender) external view returns (uint256);

  /**
   * @notice Sets the allowance of a spender from the `msg.sender` to the value `amount`
   * @param spender The account which will be allowed to spend a given amount of the owners tokens
   * @param amount The amount of tokens allowed to be used by `spender`
   * @return Returns true for a successful approval, false for unsuccessful
   **/
  function approve(address spender, uint256 amount) external returns (bool);

  /**
   * @notice Transfers `amount` tokens from `sender` to `recipient` up to the allowance given to the `msg.sender`
   * @param from The account from which the transfer will be initiated
   * @param to The recipient of the transfer
   * @param amount The amount of the transfer
   * @return Returns true for a successful transfer, false for unsuccessful
   **/
  function transferFrom(
    address from,
    address to,
    uint256 amount
  ) external returns (bool);
}
