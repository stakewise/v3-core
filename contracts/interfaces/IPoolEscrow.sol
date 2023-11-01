// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.22;

/**
 * @title IPoolEscrow
 * @author StakeWise
 * @dev Copied from https://github.com/stakewise/contracts/blob/master/contracts/interfaces/IPoolEscrow.sol
 * @notice Defines the interface for the PoolEscrow contract
 */
interface IPoolEscrow {
  /**
   * @notice Event for tracking withdrawn ether
   * @param sender The address of the transaction sender
   * @param payee The address where the funds were transferred to
   * @param amount The amount of ether transferred to payee
   */
  event Withdrawn(address indexed sender, address indexed payee, uint256 amount);

  /**
   * @notice Event for tracking ownership transfer commits
   * @param currentOwner The address of the current owner
   * @param futureOwner The address the ownership is planned to be transferred to
   */
  event OwnershipTransferCommitted(address indexed currentOwner, address indexed futureOwner);

  /**
   * @notice Event for tracking ownership transfers
   * @param previousOwner The address the ownership was transferred from
   * @param newOwner The address the ownership was transferred to
   */
  event OwnershipTransferApplied(address indexed previousOwner, address indexed newOwner);

  /**
   * @dev Function for retrieving the address of the current owner
   * @return The address of the current owner
   */
  function owner() external view returns (address);

  /**
   * @notice Function for retrieving the address of the future owner
   * @return The address of the future owner
   */
  function futureOwner() external view returns (address);

  /**
   * @notice Commit contract ownership transfer to a new account (`newOwner`). Can only be called by the current owner.
   * @param newOwner The address the ownership is planned to be transferred to
   */
  function commitOwnershipTransfer(address newOwner) external;

  /**
   * @notice Apply contract ownership transfer to a new account (`futureOwner`). Can only be called by the future owner.
   */
  function applyOwnershipTransfer() external;

  /**
   * @notice Withdraw balance for a payee, forwarding all gas to the
   *         recipient. Can only be called by the current owner.
   * @dev WARNING: Forwarding all gas opens the door to reentrancy vulnerabilities.
   *      Make sure you trust the recipient, or are either following the
   *      checks-effects-interactions pattern or using {ReentrancyGuard}.
   * @param payee The address where the funds will be transferred to
   * @param amount The amount of ether to transfer to payee
   */
  function withdraw(address payable payee, uint256 amount) external;
}
