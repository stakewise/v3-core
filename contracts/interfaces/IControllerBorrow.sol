// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.18;

/**
 * @title IControllerBorrow
 * @author StakeWise
 * @notice Defines the interface for the ControllerBorrow contract
 */
interface IControllerBorrow {
  // Custom errors
  error InvalidRecipient();
  error LowHealthFactor();
  error VaultNotHarvested();
  error NotEnoughSuppliedAssets();
  error InvalidShares();
  error InvalidVault();
  error ExceededVaultsCount();

  /**
   * @notice A struct containing user OsToken borrow position
   * @param shares The number of OsToken shares borrowed
   * @param checkpointAssets The OsToken last checkpoint assets used for protocol fee calculation
   */
  struct BorrowPosition {
    uint128 shares;
    uint128 checkpointAssets;
  }

  /**
   * @notice Event emitted on borrow
   * @param caller The address of the function caller
   * @param receiver The address of the shares receiver
   * @param assets The amount of OsToken assets collateralized
   * @param shares The amount of OsToken shares minted
   * @param referrer The address of the referrer
   */
  event Borrowed(
    address indexed caller,
    address indexed receiver,
    uint256 assets,
    uint256 shares,
    address referrer
  );

  /**
   * @notice Event emitted on repay
   * @param caller The address of the function caller
   * @param assets The amount of OsToken assets repaid
   * @param shares The amount of OsToken shares repaid
   */
  event Repaid(address indexed caller, uint256 assets, uint256 shares);

  /**
   * @notice Get user's borrow position
   * @param user The address of the user to get the position for
   * @return shares The number of OsToken shares user has borrowed.
   * @return checkpointAssets The OsToken last checkpoint assets used for protocol fee calculation
   */
  function borrowings(address user) external returns (uint128 shares, uint128 checkpointAssets);

  /**
   * @notice Get treasury accumulated fee for the Vault
   * @param vault The address of the Vault to get the fee for
   * @return shares The number of Vault shares
   * @return checkpointAssets The Vault last checkpoint assets used for treasury total assets calculation
   */
  function treasuryShares(
    address vault
  ) external returns (uint256 shares, uint256 checkpointAssets);

  /**
   * @notice Mints OsToken shares. Must be called by the Vault tokens supplier.
   * @param assets The number of underlying assets to borrow. It is converted to shares.
   * @param receiver The OsToken shares receiver
   * @param referrer The address of the referrer
   * @param assets The number of assets deposited by the caller
   * @return shares The number of shares minted to the receiver
   */
  function borrow(
    uint256 assets,
    address receiver,
    address referrer
  ) external returns (uint256 shares);

  /**
   * @notice Repays OsToken shares. Must be called by the borrow position holder.
   * @param assets The number of assets repaid
   */
  function repay(uint128 shares) external returns (uint256 assets);
}
