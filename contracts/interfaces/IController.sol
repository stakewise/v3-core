// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

/**
 * @title IController
 * @author StakeWise
 * @notice Defines the interface for the Controller contract
 */
interface IController {
  // Custom errors
  error InvalidVault();
  error InvalidShares();
  error InvalidAssets();
  error ExceededVaultsCount();
  error VaultNotHarvested();
  error InvalidRecipient();
  error LowHealthFactor();
  error LowLtv();
  error InvalidVaults();
  error HealthFactorNotViolated();
  error FailedToLiquidate();

  /**
   * @notice Event emitted on deposit
   * @param caller The address of the function caller
   * @param vault The address of the Vault
   * @param shares The amount of shares deposited
   */
  event Deposit(address indexed caller, address indexed vault, uint256 shares);

  /**
   * @notice Event emitted on withdraw
   * @param caller The address of the function caller
   * @param vault The address of the Vault
   * @param receiver The address of the vault token receiver
   * @param shares The amount of shares withdrawn
   */
  event Withdraw(address indexed caller, address indexed vault, address receiver, uint256 shares);

  /**
   * @notice Event emitted on borrow
   * @param caller The address of the function caller
   * @param receiver The address of the osToken receiver
   * @param assets The amount of borrowed assets
   * @param shares The amount of borrowed shares
   * @param referrer The address of the referrer
   */
  event Borrow(
    address indexed caller,
    address receiver,
    uint256 assets,
    uint256 shares,
    address referrer
  );

  /**
   * @notice Event emitted on repay
   * @param caller The address of the function caller
   * @param assets The amount of repaid assets
   * @param shares The amount of repaid shares
   */
  event Repay(address indexed caller, uint256 assets, uint256 shares);

  /**
   * @notice Event emitted on liquidation
   * @param caller The address of the function caller
   * @param user The address of the user liquidated
   * @param collateralReceiver The address of the collateral receiver
   * @param coveredShares The amount of covered shares
   * @param coveredAssets The amount of covered assets
   * @param receivedAssets The amount of received assets
   */
  event Liquidation(
    address indexed caller,
    address indexed user,
    address collateralReceiver,
    uint256 coveredShares,
    uint256 coveredAssets,
    uint256 receivedAssets
  );

  /**
   * @dev Structure to store user borrowed osToken shares
   * @param shares The amount of borrowed shares
   * @param cumulativeFeePerAsset The cumulative fee per asset used for treasury fee calculation
   */
  struct Borrowing {
    uint128 shares;
    uint128 cumulativeFeePerAsset;
  }

  /**
   * @notice The health factor below which position can be liquidated
   * @return The health factor liquidation threshold value
   */
  function healthFactorLiqThreshold() external view returns (uint256);

  /**
   * @notice The maximum number of vaults that can be used for borrowing
   * @return The maximum number of vaults
   */
  function maxVaultsCount() external view returns (uint256);

  /**
   * @notice The liquidation threshold percent used to calculate health factor
   * @return The liquidation threshold percent value
   */
  function liqThresholdPercent() external view returns (uint256);

  /**
   * @notice The bonus percent that liquidator earns on liquidation
   * @return The liquidation bonus percent value
   */
  function liqBonusPercent() external view returns (uint256);

  /**
   * @notice The percent used to calculate how much user can borrow
   * @return The loan-to-value (LTV) percent value
   */
  function ltvPercent() external view returns (uint256);

  /**
   * @notice Get amount of deposited shares for a specific user in a specific vault
   * @param vault The address of the vault
   * @param user The address of the user
   * @return shares The number of deposited shares
   */
  function deposits(address vault, address user) external view returns (uint256 shares);

  /**
   * @notice Get borrow position for the user
   * @param user The address of the user
   * @return shares The number of borrowed shares
   * @return cumulativeFeePerAsset The cumulative fee per asset used for treasury fee calculation
   */
  function borrowings(
    address user
  ) external view returns (uint128 shares, uint128 cumulativeFeePerAsset);

  /**
   * @notice Get list of user vaults
   * @param user The address of the user
   * @return An array of vault addresses
   */
  function vaults(address user) external view returns (address[] memory);

  /**
   * @notice Get the total number of deposited assets for a specific user
   * @param user The address of user
   * @return assets The total number of deposited assets
   */
  function getDepositedAssets(address user) external view returns (uint256 assets);

  /**
   * @notice Deposits Vault shares for osToken borrowing. Only up to 10 vaults can be used.
   * @param vault The address of the vault
   * @param shares The number of shares to deposit
   */
  function deposit(address vault, uint256 shares) external;

  /**
   * @notice Withdraws Vault shares, and optionally redeems and sends vault tokens to the exit queue
   * @param vault The address of the vault
   * @param receiver The receiver address
   * @param shares The number of shares to withdraw
   * @param redeemAndEnterExitQueue Whether to redeem and send vault tokens to the exit queue
   */
  function withdraw(
    address vault,
    address receiver,
    uint256 shares,
    bool redeemAndEnterExitQueue
  ) external;

  /**
   * @notice Borrows OsToken shares
   * @param assets The number of OsToken assets to borrow
   * @param receiver The address of the receiver
   * @param referrer The address of the referrer
   * @return shares The number of OsToken shares minted to the receiver
   */
  function borrow(
    uint256 assets,
    address receiver,
    address referrer
  ) external returns (uint256 shares);

  /**
   * @notice Repays the borrowed shares and returns the number of repaid assets
   * @param shares The number of shares to repay
   * @return assets The number of repaid assets
   */
  function repay(uint128 shares) external returns (uint256 assets);

  /**
   * @notice Liquidates a user position and returns the number of covered assets
   * @param user The address of the user to liquidate the position for
   * @param coveredShares The number of shares to cover
   * @param sortedVaults The list of vaults sorted by the priority of the received collaterals
   * @param collateralReceiver The address of the collateral receiver
   * @param redeemAndEnterExitQueue Whether to redeem and send collaterals to the exit queue
   * @return coveredAssets The number of assets covered
   */
  function liquidate(
    address user,
    uint256 coveredShares,
    address[] calldata sortedVaults,
    address collateralReceiver,
    bool redeemAndEnterExitQueue
  ) external returns (uint256 coveredAssets);

  /**
   * @notice Syncs the treasury fee for the borrowing position
   * @param user The address of the user to sync the fee for
   * @return borrowedShares The number of borrowed shares after sync
   */
  function syncBorrowing(address user) external returns (uint256 borrowedShares);
}
