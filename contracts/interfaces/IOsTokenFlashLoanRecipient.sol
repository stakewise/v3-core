// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

/**
 * @title IOsTokenFlashLoanRecipient
 * @author StakeWise
 * @notice Interface for OsTokenFlashLoanRecipient contract
 */
interface IOsTokenFlashLoanRecipient {
  /**
   * @notice Receive flash loan hook
   * @param osTokenShares The osToken flash loan amount
   * @param userData Arbitrary data passed to the hook
   */
  function receiveFlashLoan(uint256 osTokenShares, bytes memory userData) external;
}
