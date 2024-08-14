// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {IOsTokenVaultEscrow} from '../interfaces/IOsTokenVaultEscrow.sol';
import {IOsTokenVaultController} from '../interfaces/IOsTokenVaultController.sol';
import {IVaultsRegistry} from '../interfaces/IVaultsRegistry.sol';
import {IVaultEnterExit} from '../interfaces/IVaultEnterExit.sol';
import {IOsTokenConfig} from '../interfaces/IOsTokenConfig.sol';
import {Errors} from '../libraries/Errors.sol';
import {Multicall} from '../base/Multicall.sol';

/**
 * @title OsTokenVaultEscrow
 * @author StakeWise
 * @notice Used for initiating assets exits from the vault without burning osToken
 */
abstract contract OsTokenVaultEscrow is Multicall, IOsTokenVaultEscrow {
  uint256 private constant _maxPercent = 1e18;
  uint256 private constant _wad = 1e18;
  uint256 private constant _hfLiqThreshold = 1e18;
  uint256 private constant _disabledLiqThreshold = type(uint64).max;

  IVaultsRegistry internal immutable _vaultsRegistry;
  IOsTokenVaultController private immutable _osTokenVaultController;
  IOsTokenConfig private immutable _osTokenConfig;

  mapping(address vault => mapping(uint256 positionTicket => Position)) private _positions;

  /**
   * @dev Constructor
   * @param vaultsRegistry The address of the VaultsRegistry contract
   * @param osTokenVaultController The address of the OsTokenVaultController contract
   * @param osTokenConfig The address of the OsTokenConfig contract
   */
  constructor(address vaultsRegistry, address osTokenVaultController, address osTokenConfig) {
    _vaultsRegistry = IVaultsRegistry(vaultsRegistry);
    _osTokenVaultController = IOsTokenVaultController(osTokenVaultController);
    _osTokenConfig = IOsTokenConfig(osTokenConfig);
  }

  /// @inheritdoc IOsTokenVaultEscrow
  function getPosition(
    address vault,
    uint256 positionTicket
  ) external view returns (uint256, uint256) {
    Position memory position = _positions[vault][positionTicket];
    _syncPositionFee(position);
    return (position.exitedAssets, position.osTokenShares);
  }

  /// @inheritdoc IOsTokenVaultEscrow
  function register(
    address owner,
    uint256 exitPositionTicket,
    uint128 osTokenShares,
    uint128 cumulativeFeePerShare
  ) external override {
    // check if caller is a vault
    if (!_vaultsRegistry.vaults(msg.sender)) {
      revert Errors.AccessDenied();
    }

    // check owner and shares are not zero
    if (owner == address(0)) revert Errors.ZeroAddress();
    if (osTokenShares == 0) revert Errors.InvalidShares();

    // create new position
    _positions[msg.sender][exitPositionTicket] = Position({
      owner: owner,
      exitedAssets: 0,
      osTokenShares: osTokenShares,
      cumulativeFeePerShare: cumulativeFeePerShare
    });

    // emit event
    emit PositionCreated(
      msg.sender,
      exitPositionTicket,
      owner,
      osTokenShares,
      cumulativeFeePerShare
    );
  }

  /// @inheritdoc IOsTokenVaultEscrow
  function processExitedAssets(
    address vault,
    uint256 exitPositionTicket,
    uint256 timestamp
  ) external override {
    // get position
    Position storage position = _positions[vault][exitPositionTicket];
    if (position.owner == address(0)) revert Errors.InvalidPosition();

    // claim exited assets
    (uint256 leftTickets, , uint256 exitedAssets) = IVaultEnterExit(vault).calculateExitedAssets(
      address(this),
      exitPositionTicket,
      timestamp,
      0
    );
    // the exit request must be fully processed (1 ticket could be a rounding error)
    if (leftTickets > 1) revert Errors.ExitRequestNotProcessed();
    IVaultEnterExit(vault).claimExitedAssets(exitPositionTicket, timestamp, 0);

    // update position
    position.exitedAssets = SafeCast.toUint96(exitedAssets);

    // emit event
    emit ExitedAssetsProcessed(vault, exitPositionTicket, exitedAssets);
  }

  /// @inheritdoc IOsTokenVaultEscrow
  function claimExitedAssets(
    address vault,
    uint256 exitPositionTicket,
    uint256 osTokenShares
  ) external override {
    // burn osToken shares
    _osTokenVaultController.burnShares(msg.sender, osTokenShares);

    // fetch user position
    Position memory position = _positions[vault][exitPositionTicket];
    if (msg.sender != position.owner) revert Errors.AccessDenied();

    // check whether position exists and there are enough osToken shares
    _syncPositionFee(position);
    if (position.osTokenShares == 0 || position.osTokenShares < osTokenShares) {
      revert Errors.InvalidShares();
    }

    // calculate assets to withdraw
    uint256 assetsToTransfer;
    if (position.osTokenShares != osTokenShares) {
      assetsToTransfer = Math.mulDiv(position.exitedAssets, osTokenShares, position.osTokenShares);

      // update position osTokenShares
      position.osTokenShares -= SafeCast.toUint128(osTokenShares);
      _positions[vault][exitPositionTicket] = position;
    } else {
      assetsToTransfer = position.exitedAssets;

      // remove position as it is fully processed
      delete _positions[vault][exitPositionTicket];
    }
    if (assetsToTransfer == 0) revert Errors.ExitRequestNotProcessed();

    // transfer assets
    _transferAssets(position.owner, assetsToTransfer);

    // emit event
    emit ExitedAssetsClaimed(
      msg.sender,
      vault,
      exitPositionTicket,
      osTokenShares,
      assetsToTransfer
    );
  }

  /// @inheritdoc IOsTokenVaultEscrow
  function liquidateOsToken(
    address vault,
    uint256 exitPositionTicket,
    uint256 osTokenShares,
    address receiver
  ) external override {
    uint256 receivedAssets = _redeemOsToken(
      vault,
      exitPositionTicket,
      receiver,
      osTokenShares,
      true
    );
    emit OsTokenLiquidated(
      msg.sender,
      vault,
      exitPositionTicket,
      receiver,
      osTokenShares,
      receivedAssets
    );
  }

  /// @inheritdoc IOsTokenVaultEscrow
  function redeemOsToken(
    address vault,
    uint256 exitPositionTicket,
    uint256 osTokenShares,
    address receiver
  ) external override {
    if (msg.sender != _osTokenConfig.redeemer()) revert Errors.AccessDenied();
    uint256 receivedAssets = _redeemOsToken(
      vault,
      exitPositionTicket,
      receiver,
      osTokenShares,
      false
    );
    emit OsTokenRedeemed(
      msg.sender,
      vault,
      exitPositionTicket,
      receiver,
      osTokenShares,
      receivedAssets
    );
  }

  /**
   * @dev Internal function for redeeming osToken shares
   * @param vault The address of the vault
   * @param exitPositionTicket The position ticket of the exit queue
   * @param receiver The address of the receiver of the redeemed assets
   * @param osTokenShares The amount of osToken shares to redeem
   * @param isLiquidation Whether the redeem is a liquidation
   */
  function _redeemOsToken(
    address vault,
    uint256 exitPositionTicket,
    address receiver,
    uint256 osTokenShares,
    bool isLiquidation
  ) private returns (uint256 receivedAssets) {
    if (receiver == address(0)) revert Errors.ZeroAddress();

    // update osToken state for gas efficiency
    _osTokenVaultController.updateState();

    // fetch user position
    Position memory position = _positions[vault][exitPositionTicket];
    if (position.osTokenShares == 0) revert Errors.InvalidPosition();
    _syncPositionFee(position);

    // SLOAD to memory
    IOsTokenConfig.Config memory osTokenConfig = _osTokenConfig.getConfig(vault);
    if (isLiquidation && osTokenConfig.liqThresholdPercent == _disabledLiqThreshold) {
      revert Errors.LiquidationDisabled();
    }

    // calculate received assets
    if (isLiquidation) {
      receivedAssets = Math.mulDiv(
        _osTokenVaultController.convertToAssets(osTokenShares),
        osTokenConfig.liqBonusPercent,
        _maxPercent
      );
    } else {
      receivedAssets = _osTokenVaultController.convertToAssets(osTokenShares);
    }

    {
      // check whether received assets are valid
      if (receivedAssets > position.exitedAssets) {
        revert Errors.InvalidReceivedAssets();
      }

      uint256 mintedAssets = _osTokenVaultController.convertToAssets(position.osTokenShares);
      if (isLiquidation) {
        // check health factor violation in case of liquidation
        if (
          Math.mulDiv(
            position.exitedAssets * _wad,
            osTokenConfig.liqThresholdPercent,
            mintedAssets * _maxPercent
          ) >= _hfLiqThreshold
        ) {
          revert Errors.InvalidHealthFactor();
        }
      }
    }

    // reduce osToken supply
    _osTokenVaultController.burnShares(msg.sender, osTokenShares);

    // update position
    position.osTokenShares -= SafeCast.toUint128(osTokenShares);
    _positions[vault][exitPositionTicket] = position;

    // transfer assets to the receiver
    _transferAssets(receiver, receivedAssets);
  }

  /**
   * @dev Internal function for syncing the osToken fee
   * @param position The position to sync the fee for
   */
  function _syncPositionFee(Position memory position) private view {
    // fetch current cumulative fee per share
    uint256 cumulativeFeePerShare = _osTokenVaultController.cumulativeFeePerShare();

    // check whether fee is already up to date
    if (cumulativeFeePerShare == position.cumulativeFeePerShare) return;

    // add treasury fee to the position
    position.osTokenShares = SafeCast.toUint128(
      Math.mulDiv(position.osTokenShares, cumulativeFeePerShare, position.cumulativeFeePerShare)
    );
    position.cumulativeFeePerShare = SafeCast.toUint128(cumulativeFeePerShare);
  }

  /**
   * @dev Internal function for transferring assets from the Vault to the receiver
   * @dev IMPORTANT: because control is transferred to the receiver, care must be
   *    taken to not create reentrancy vulnerabilities. The Vault must follow the checks-effects-interactions pattern:
   *    https://docs.soliditylang.org/en/v0.8.22/security-considerations.html#use-the-checks-effects-interactions-pattern
   * @param receiver The address that will receive the assets
   * @param assets The number of assets to transfer
   */
  function _transferAssets(address receiver, uint256 assets) internal virtual;
}
