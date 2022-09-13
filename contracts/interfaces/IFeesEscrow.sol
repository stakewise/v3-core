// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

/**
 * @title IFeesEscrow
 * @author StakeWise
 * @notice Defines the interface for the FeesEscrow contract
 */
interface IFeesEscrow {
  error WithdrawalFailed();

  /**
   * @notice Withdraws MEV and priority fees accumulated in the escrow.
             Can perform additional conversions in case different asset is staked.
   * @dev IMPORTANT: because control is transferred to the Vault, care must be
   *    taken to not create reentrancy vulnerabilities. The Vault must follow the checks-effects-interactions pattern:
   *    https://docs.soliditylang.org/en/v0.8.17/security-considerations.html#use-the-checks-effects-interactions-pattern
   * @return assets The amount of assets withdrawn
   */
  function withdraw() external returns (uint256 assets);
}
