// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity =0.8.22;

/**
 * @title IGnoPoolEscrow
 * @author StakeWise
 * @dev Copied from https://github.com/stakewise/contracts/blob/gnosis-chain/contracts/interfaces/IPoolEscrow.sol
 * @notice Defines the interface for the PoolEscrow contract on Gnosis
 */
interface IGnoPoolEscrow {
  /**
   * @dev Event for tracking withdrawals.
   * @param sender - the address of the transaction sender.
   * @param payee - the address where the funds were transferred to.
   * @param amount - the amount transferred to payee.
   */
  event Withdrawn(address indexed sender, address indexed payee, uint256 amount);

  /**
   * @dev Event for tracking ownership transfer commits.
   * @param currentOwner - the address of the current owner.
   * @param futureOwner - the address the ownership is planned to be transferred to.
   */
  event OwnershipTransferCommitted(address indexed currentOwner, address indexed futureOwner);

  /**
   * @dev Event for tracking ownership transfers.
   * @param previousOwner - the address the ownership was transferred from.
   * @param newOwner - the address the ownership was transferred to.
   */
  event OwnershipTransferApplied(address indexed previousOwner, address indexed newOwner);

  /**
   * @dev Function for retrieving the address of the current owner.
   */
  function owner() external view returns (address);

  /**
   * @dev Function for retrieving the address of the future owner.
   */
  function futureOwner() external view returns (address);

  /**
   * @dev Commit contract ownership transfer to a new account (`newOwner`).
   * Can only be called by the current owner.
   */
  function commitOwnershipTransfer(address newOwner) external;

  /**
   * @dev Apply contract ownership transfer to a new account (`futureOwner`).
   * Can only be called by the future owner.
   */
  function applyOwnershipTransfer() external;

  /**
   * @dev Withdraw tokens from the escrow. Can only be called by the current owner.
   * @param token - the address of the token to transfer.
   * @param payee - the address where the funds will be transferred to.
   * @param amount - the amount of tokens to transfer to payee.
   */
  function withdrawTokens(address token, address payee, uint256 amount) external;

  /**
   * @dev Withdraw balance for a payee, forwarding all gas to the
   * recipient. Can only be called by the current owner.
   *
   * WARNING: Forwarding all gas opens the door to reentrancy vulnerabilities.
   * Make sure you trust the recipient, or are either following the
   * checks-effects-interactions pattern or using {ReentrancyGuard}.
   *
   * @param payee - the address where the funds will be transferred to.
   * @param amount - the amount of xDAI to transfer to payee.
   */
  function withdraw(address payable payee, uint256 amount) external;
}
