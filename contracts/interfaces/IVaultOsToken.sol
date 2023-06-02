// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {IVaultToken} from './IVaultToken.sol';
import {IVaultEnterExit} from './IVaultEnterExit.sol';

/**
 * @title IVaultOsToken
 * @author StakeWise
 * @notice Defines the interface for the VaultOsToken contract
 */
interface IVaultOsToken is IVaultToken, IVaultEnterExit {
  // Custom errors
  error HealthFactorNotViolated();
  error InvalidHealthFactor();
  error InvalidLtv();
  error RedemptionExceeded();
  error InvalidReceivedAssets();
  error InvalidPosition();
  error LowLtv();

  /**
   * @notice Event emitted on minting osToken
   * @param caller The address of the function caller
   * @param receiver The address of the osToken receiver
   * @param assets The amount of minted assets
   * @param shares The amount of minted shares
   * @param referrer The address of the referrer
   */
  event OsTokenMinted(
    address indexed caller,
    address receiver,
    uint256 assets,
    uint256 shares,
    address referrer
  );

  /**
   * @notice Event emitted on burning OsToken
   * @param caller The address of the function caller
   * @param assets The amount of burned assets
   * @param shares The amount of burned shares
   */
  event OsTokenBurned(address indexed caller, uint256 assets, uint256 shares);

  /**
   * @notice Event emitted on osToken position liquidation
   * @param caller The address of the function caller
   * @param user The address of the user liquidated
   * @param receiver The address of the receiver of the liquidated assets
   * @param coveredShares The amount of covered shares
   * @param receivedAssets The amount of assets received
   */
  event OsTokenLiquidated(
    address indexed caller,
    address indexed user,
    address receiver,
    uint256 coveredShares,
    uint256 receivedAssets
  );

  /**
   * @notice Event emitted on osToken position redemption
   * @param caller The address of the function caller
   * @param user The address of the position owner to redeem from
   * @param receiver The address of the receiver of the redeemed assets
   * @param shares The amount of shares to redeem
   * @param assets The amount of assets received
   */
  event OsTokenRedeemed(
    address indexed caller,
    address indexed user,
    address receiver,
    uint256 shares,
    uint256 assets
  );

  /**
   * @notice Struct of osToken position
   * @param shares The total number of minted osToken shares. Will increase based on the treasury fee.
   * @param cumulativeFeePerShare The cumulative fee per share
   */
  struct OsTokenPosition {
    uint128 shares;
    uint128 cumulativeFeePerShare;
  }

  /**
   * @notice Get total amount of minted osToken shares
   * @param user The address of the user
   * @return shares The number of minted osToken shares
   */
  function osTokenPositions(address user) external view returns (uint128 shares);

  /**
   * @notice Mints OsToken shares
   * @param receiver The address that will receive the minted OsToken shares
   * @param assets The number of assets to calculate the number of OsToken shares to mint
   * @param referrer The address of the referrer
   * @return shares The number of OsToken shares minted to the receiver
   */
  function mintOsToken(
    address receiver,
    uint256 assets,
    address referrer
  ) external returns (uint256 shares);

  /**
   * @notice Burns osToken shares
   * @param osTokenShares The number of shares to burn
   * @return assets The number of assets burned
   */
  function burnOsToken(uint128 osTokenShares) external returns (uint256 assets);

  /**
   * @notice Liquidates a user position and returns the number of received assets.
   *         Can only be called when health factor is below 1.
   * @param osTokenShares The number of shares to cover
   * @param owner The address of the position owner to liquidate
   * @param receiver The address of the receiver of the liquidated assets
   * @return receivedAssets The number of assets received
   */
  function liquidateOsToken(
    uint256 osTokenShares,
    address owner,
    address receiver
  ) external returns (uint256 receivedAssets);

  /**
   * @notice Redeems osToken shares for assets. Can only be called when health factor is above redeemFromHealthFactor.
   * @param osTokenShares The number of osToken shares to redeem
   * @param owner The address of the position owner to redeem from
   * @param receiver The address of the receiver of the redeemed assets
   * @return receivedAssets The number of assets received
   */
  function redeemOsToken(
    uint256 osTokenShares,
    address owner,
    address receiver
  ) external returns (uint256 receivedAssets);
}
