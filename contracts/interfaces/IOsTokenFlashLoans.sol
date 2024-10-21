// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

/**
 * @title IOsTokenFlashLoans
 * @author StakeWise
 * @notice Interface for OsTokenFlashLoans contract
 */
interface IOsTokenFlashLoans {
  /**
   * @notice Event emitted on flash loan
   * @param caller The address of the caller
   * @param amount The flashLoan osToken shares amount
   */
  event OsTokenFlashLoan(address indexed caller, uint256 amount);

  /**
   * @notice Flash loan OsToken shares
   * @param osTokenShares The flashLoan osToken shares amount
   * @param userData Arbitrary data passed to the `IOsTokenFlashLoanRecipient.receiveFlashLoan` function
   */
  function flashLoan(uint256 osTokenShares, bytes memory userData) external;
}
