// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

/**
 * @title IOsTokenFlashLoans
 * @author StakeWise
 * @notice Interface for OsTokenFlashLoans contract
 */
interface IOsTokenFlashLoans {
  /**
   * @notice Event emitted on position creation
   * @param recipient The address of the recipient
   * @param amount The flashLoan osToken shares amount
   */
  event OsTokenFlashLoan(address indexed recipient, uint256 amount);

  /**
   * @notice Flash loan OsToken shares
   * @param recipient The address of the recipient
   * @param amount The flashLoan osToken shares amount
   * @param userData Arbitrary data passed to the `IOsTokenFlashLoanRecipient.receiveFlashLoan` function
   */
  function flashLoan(address recipient, uint256 amount, bytes memory userData) external;
}
