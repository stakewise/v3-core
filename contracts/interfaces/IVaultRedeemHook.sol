// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

/**
 * @title IVaultRedeemHook
 * @author StakeWise
 * @notice Defines the interface for Vault hook used to redeem shares
 */
interface IVaultRedeemHook {
  /**
   * @notice The function that uses received assets to acquire shares for burn
   * @param caller The address that called the redeem function
   * @param shares The number of Vault shares to get
   * @param assets The number of assets received
   * @param params The encoded parameters for the hook
   * @return success True if the hook executed successfully
   */
  function execute(
    address caller,
    uint256 shares,
    uint256 assets,
    bytes calldata params
  ) external returns (bool);
}
