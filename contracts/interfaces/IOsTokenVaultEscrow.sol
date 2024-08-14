// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

/**
 * @title IOsTokenVaultEscrow
 * @author StakeWise
 * @notice Interface for OsTokenVaultEscrow contract
 */
interface IOsTokenVaultEscrow {
  /**
   * @notice Struct to store the escrow position details
   * @param owner The address of the assets owner
   * @param exitedAssets The amount of assets exited and ready to be claimed
   * @param osTokenShares The amount of osToken shares
   * @param cumulativeFeePerShare The cumulative fee per share used to calculate the osToken fee
   */
  struct Position {
    address owner;
    uint96 exitedAssets;
    uint128 osTokenShares;
    uint128 cumulativeFeePerShare;
  }

  /**
   * @notice Event emitted on position creation
   * @param vault The address of the vault
   * @param exitPositionTicket The exit position ticket
   * @param owner The address of the assets owner
   * @param osTokenShares The amount of osToken shares
   * @param cumulativeFeePerShare The cumulative fee per share used to calculate the osToken fee
   */
  event PositionCreated(
    address indexed vault,
    uint256 indexed exitPositionTicket,
    address owner,
    uint128 osTokenShares,
    uint128 cumulativeFeePerShare
  );

  /**
   * @notice Event emitted on assets exit processing
   * @param vault The address of the vault
   * @param exitPositionTicket The exit position ticket
   * @param exitedAssets The amount of exited assets claimed
   */
  event ExitedAssetsProcessed(
    address indexed vault,
    uint256 indexed exitPositionTicket,
    uint256 exitedAssets
  );

  /**
   * @notice Event emitted on osToken liquidation
   * @param caller The address of the function caller
   * @param vault The address of the vault
   * @param exitPositionTicket The exit position ticket
   * @param receiver The address of the receiver of the liquidated assets
   * @param osTokenShares The amount of osToken shares to liquidate
   * @param receivedAssets The amount of assets received
   */
  event OsTokenLiquidated(
    address indexed caller,
    address indexed vault,
    uint256 indexed exitPositionTicket,
    address receiver,
    uint256 osTokenShares,
    uint256 receivedAssets
  );

  /**
   * @notice Event emitted on osToken redemption
   * @param caller The address of the function caller
   * @param vault The address of the vault
   * @param exitPositionTicket The exit position ticket
   * @param receiver The address of the receiver of the redeemed assets
   * @param osTokenShares The amount of osToken shares to redeem
   * @param receivedAssets The amount of assets received
   */
  event OsTokenRedeemed(
    address indexed caller,
    address indexed vault,
    uint256 indexed exitPositionTicket,
    address receiver,
    uint256 osTokenShares,
    uint256 receivedAssets
  );

  /**
   * @notice Event emitted on exited assets claim
   * @param receiver The address of the receiver of the exited assets
   * @param vault The address of the vault
   * @param exitPositionTicket The exit position ticket
   * @param osTokenShares The amount of osToken shares burned
   * @param assets The amount of assets claimed
   */
  event ExitedAssetsClaimed(
    address indexed receiver,
    address indexed vault,
    uint256 indexed exitPositionTicket,
    uint256 osTokenShares,
    uint256 assets
  );

  /**
   * @notice Get the position details
   * @param vault The address of the vault
   * @param positionTicket The exit position ticket
   * @return exitedAssets The amount of assets exited and ready to be claimed
   * @return osTokenShares The amount of osToken shares
   */
  function getPosition(
    address vault,
    uint256 positionTicket
  ) external view returns (uint256, uint256);

  /**
   * @notice Registers the new escrow position
   * @param owner The address of the exited assets owner
   * @param exitPositionTicket The exit position ticket
   * @param osTokenShares The amount of osToken shares
   * @param cumulativeFeePerShare The cumulative fee per share used to calculate the osToken fee
   */
  function register(
    address owner,
    uint256 exitPositionTicket,
    uint128 osTokenShares,
    uint128 cumulativeFeePerShare
  ) external;

  /**
   * @notice Claims exited assets from the vault to the escrow
   * @param vault The address of the vault
   * @param exitPositionTicket The exit position ticket
   * @param timestamp The timestamp of the exit
   */
  function processExitedAssets(
    address vault,
    uint256 exitPositionTicket,
    uint256 timestamp
  ) external;

  /**
   * @notice Claims the exited assets from the escrow to the owner. Can only be called by the position owner.
   * @param vault The address of the vault
   * @param exitPositionTicket The exit position ticket
   * @param osTokenShares The amount of osToken shares to burn
   */
  function claimExitedAssets(
    address vault,
    uint256 exitPositionTicket,
    uint256 osTokenShares
  ) external;

  /**
   * @notice Liquidates the osToken shares
   * @param vault The address of the vault
   * @param exitPositionTicket The exit position ticket
   * @param osTokenShares The amount of osToken shares to liquidate
   * @param receiver The address of the receiver of the liquidated assets
   */
  function liquidateOsToken(
    address vault,
    uint256 exitPositionTicket,
    uint256 osTokenShares,
    address receiver
  ) external;

  /**
   * @notice Redeems the osToken shares. Can only be called by the osToken redeemer.
   * @param vault The address of the vault
   * @param exitPositionTicket The exit position ticket
   * @param osTokenShares The amount of osToken shares to redeem
   * @param receiver The address of the receiver of the redeemed assets
   */
  function redeemOsToken(
    address vault,
    uint256 exitPositionTicket,
    uint256 osTokenShares,
    address receiver
  ) external;
}
