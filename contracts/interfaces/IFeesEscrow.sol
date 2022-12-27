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
   * @notice Event emitted on deposits
   * @param amount The amount of fees deposited
   */
  event Deposited(uint256 amount);

  /**
   * @notice Withdraws MEV and priority fees accumulated in the escrow.
             Can perform additional conversions in case different asset is staked.
   * @dev IMPORTANT: because control is transferred to the Vault, care must be
   *    taken to not create reentrancy vulnerabilities. The Vault must follow the checks-effects-interactions pattern:
   *    https://docs.soliditylang.org/en/v0.8.17/security-considerations.html#use-the-checks-effects-interactions-pattern
   * @return assets The amount of assets withdrawn
   */
  function withdraw() external returns (uint256 assets);

  /**
   * @notice The balance of the FeesEscrow
   * @return The accumulated fees amount
   */
  function balance() external view returns (uint256);
}
