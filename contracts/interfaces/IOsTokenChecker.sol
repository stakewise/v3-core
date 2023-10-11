// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

/**
 * @title IOsTokenChecker
 * @author StakeWise
 * @notice Defines the interface for the OsTokenChecker contract
 */
interface IOsTokenChecker {
  /**
   * @notice Checks if address can mint OsToken shares
   * @param addr The address to check
   * @return `true` if address can mint shares, `false` otherwise
   */
  function canMintShares(address addr) external view returns (bool);

  /**
   * @notice Checks if address can burn OsToken shares
   * @param addr The address to check
   * @return `true` if address can burn shares, `false` otherwise
   */
  function canBurnShares(address addr) external view returns (bool);
}
