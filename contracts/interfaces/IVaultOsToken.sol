// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IVaultState} from './IVaultState.sol';
import {IVaultEnterExit} from './IVaultEnterExit.sol';

/**
 * @title IVaultOsToken
 * @author StakeWise
 * @notice Defines the interface for the VaultOsToken contract
 */
interface IVaultOsToken is IVaultState, IVaultEnterExit {
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
   * @param osTokenShares The amount of osToken shares to liquidate
   * @param shares The amount of vault shares burned
   * @param receivedAssets The amount of assets received
   */
  event OsTokenLiquidated(
    address indexed caller,
    address indexed user,
    address receiver,
    uint256 osTokenShares,
    uint256 shares,
    uint256 receivedAssets
  );

  /**
   * @notice Event emitted on osToken position redemption
   * @param caller The address of the function caller
   * @param user The address of the position owner to redeem from
   * @param receiver The address of the receiver of the redeemed assets
   * @param osTokenShares The amount of osToken shares to redeem
   * @param shares The amount of vault shares burned
   * @param assets The amount of assets received
   */
  event OsTokenRedeemed(
    address indexed caller,
    address indexed user,
    address receiver,
    uint256 osTokenShares,
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
   * @param osTokenShares The number of OsToken shares to mint to the receiver
   * @param referrer The address of the referrer
   * @return assets The number of assets minted to the receiver
   */
  function mintOsToken(
    address receiver,
    uint256 osTokenShares,
    address referrer
  ) external returns (uint256 assets);

  /**
   * @notice Burns osToken shares
   * @param osTokenShares The number of shares to burn
   * @return assets The number of assets burned
   */
  function burnOsToken(uint128 osTokenShares) external returns (uint256 assets);

  /**
   * @notice Liquidates a user position and returns the number of received assets.
   *         Can only be called when health factor is below 1 by the liquidator.
   * @param osTokenShares The number of shares to cover
   * @param owner The address of the position owner to liquidate
   * @param receiver The address of the receiver of the liquidated assets
   */
  function liquidateOsToken(uint256 osTokenShares, address owner, address receiver) external;

  /**
   * @notice Redeems osToken shares for assets. Can only be called when health factor is above redeemFromHealthFactor by the redeemer.
   * @param osTokenShares The number of osToken shares to redeem
   * @param owner The address of the position owner to redeem from
   * @param receiver The address of the receiver of the redeemed assets
   */
  function redeemOsToken(uint256 osTokenShares, address owner, address receiver) external;
}
