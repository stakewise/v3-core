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
  error InvalidRedeemStartHealthFactor();
  error InvalidRedeemMaxHealthFactor();
  error ReceivedAssetsExceedDeposit();
  error RedeemHookFailed();
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
   * @param coveredShares The amount of covered shares
   * @param receivedAssets The amount of assets received
   */
  event OsTokenLiquidated(
    address indexed caller,
    address indexed user,
    uint256 coveredShares,
    uint256 receivedAssets
  );

  /**
   * @notice Event emitted on osToken position redemption
   * @param caller The address of the function caller
   * @param user The address of the position owner to redeem from
   * @param shares The amount of shares to redeem
   * @param assets The amount of assets received
   */
  event OsTokenRedeemed(
    address indexed caller,
    address indexed user,
    uint256 shares,
    uint256 assets
  );

  struct OsTokenPosition {
    uint128 shares;
    uint128 cumulativeFeePerShare;
  }

  /**
   * @notice Get osToken position for the user
   * @param user The address of the user
   * @return shares The number of minted osToken shares
   */
  function osTokenPositions(address user) external view returns (uint128 shares);

  /**
   * @notice Get the number of locked assets for the user
   * @param user The address of the user
   * @return assets The number of locked assets
   */
  function lockedAssets(address user) external view returns (uint256 assets);

  /**
   * @notice Mints OsToken shares
   * @param receiver The address of the receiver
   * @param assets The number of OsToken assets to mint
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
   * @notice Liquidates a user position and returns the number of received assets. Can only be executor by the liquidator.
   * @param user The address of the user to liquidate the position for
   * @param osTokenShares The number of shares to cover
   * @return receivedAssets The number of assets received
   */
  function liquidateOsToken(
    address user,
    uint256 osTokenShares
  ) external returns (uint256 receivedAssets);

  /**
   * @notice Redeems osToken shares for assets. Can only be called by the redeemer.
   * @param user The address of the user to redeem the shares for
   * @param osTokenShares The number of osToken shares to redeem
   * @return assets The number of assets received
   */
  function redeemOsToken(address user, uint256 osTokenShares) external returns (uint256 assets);

  /**
   * @notice Redeems assets from the Vault by utilising what has not been staked yet with the hook call.
             The hook can be used to buy osToken shares from the market and call redeemOsToken or liquidateOsToken.
   * @param shares The number of shares to burn
   * @param hook The hook that receives the assets in advance and must have required amount of shares
   * @param params The additional parameters to pass to the hook
   * @return assets The number of assets withdrawn
   */
  function redeemWithHook(
    uint256 shares,
    address hook,
    bytes calldata params
  ) external returns (uint256 assets);
}
