// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IOsTokenVaultEscrow} from "../interfaces/IOsTokenVaultEscrow.sol";
import {IOsTokenVaultController} from "../interfaces/IOsTokenVaultController.sol";
import {IVaultEnterExit} from "../interfaces/IVaultEnterExit.sol";
import {IOsTokenConfig} from "../interfaces/IOsTokenConfig.sol";
import {IOsTokenVaultEscrowAuth} from "../interfaces/IOsTokenVaultEscrowAuth.sol";
import {Errors} from "../libraries/Errors.sol";
import {Multicall} from "../base/Multicall.sol";

/**
 * @title OsTokenVaultEscrow
 * @author StakeWise
 * @notice Used for initiating assets exits from the vault without burning osToken
 */
abstract contract OsTokenVaultEscrow is Ownable2Step, Multicall, IOsTokenVaultEscrow {
    uint256 private constant _maxPercent = 1e18;
    uint256 private constant _wad = 1e18;
    uint256 private constant _hfLiqThreshold = 1e18;

    IOsTokenVaultController private immutable _osTokenVaultController;
    IOsTokenConfig private immutable _osTokenConfig;

    mapping(address vault => mapping(uint256 positionTicket => Position)) private _positions;

    /// @inheritdoc IOsTokenVaultEscrow
    uint256 public override liqBonusPercent;

    /// @inheritdoc IOsTokenVaultEscrow
    address public override authenticator;

    /// @inheritdoc IOsTokenVaultEscrow
    uint64 public override liqThresholdPercent;

    /**
     * @dev Constructor
     * @param osTokenVaultController The address of the OsTokenVaultController contract
     * @param osTokenConfig The address of the OsTokenConfig contract
     * @param initialOwner The address of the contract owner
     * @param _authenticator The address of the OsTokenVaultEscrowAuth contract
     * @param _liqThresholdPercent The liquidation threshold percent
     * @param _liqBonusPercent The liquidation bonus percent
     */
    constructor(
        address osTokenVaultController,
        address osTokenConfig,
        address initialOwner,
        address _authenticator,
        uint64 _liqThresholdPercent,
        uint256 _liqBonusPercent
    ) Ownable(msg.sender) {
        _osTokenVaultController = IOsTokenVaultController(osTokenVaultController);
        _osTokenConfig = IOsTokenConfig(osTokenConfig);
        updateLiqConfig(_liqThresholdPercent, _liqBonusPercent);
        setAuthenticator(_authenticator);
        _transferOwnership(initialOwner);
    }

    /// @inheritdoc IOsTokenVaultEscrow
    function getPosition(address vault, uint256 positionTicket) external view returns (address, uint256, uint256) {
        Position memory position = _positions[vault][positionTicket];
        if (position.osTokenShares != 0) {
            _syncPositionFee(position);
        }
        return (position.owner, position.exitedAssets, position.osTokenShares);
    }

    /// @inheritdoc IOsTokenVaultEscrow
    function register(address owner, uint256 exitPositionTicket, uint256 osTokenShares, uint256 cumulativeFeePerShare)
        external
        override
    {
        // check if caller has permission
        if (!IOsTokenVaultEscrowAuth(authenticator).canRegister(msg.sender, owner, exitPositionTicket, osTokenShares)) {
            revert Errors.AccessDenied();
        }

        // check owner and shares are not zero
        if (owner == address(0)) revert Errors.ZeroAddress();
        if (osTokenShares == 0) revert Errors.InvalidShares();

        // create new position
        _positions[msg.sender][exitPositionTicket] = Position({
            owner: owner,
            exitedAssets: 0,
            osTokenShares: SafeCast.toUint128(osTokenShares),
            cumulativeFeePerShare: SafeCast.toUint128(cumulativeFeePerShare)
        });

        // emit event
        emit PositionCreated(msg.sender, exitPositionTicket, owner, osTokenShares, cumulativeFeePerShare);
    }

    /// @inheritdoc IOsTokenVaultEscrow
    function processExitedAssets(address vault, uint256 exitPositionTicket, uint256 timestamp, uint256 exitQueueIndex)
        external
        override
    {
        // get position
        Position storage position = _positions[vault][exitPositionTicket];
        if (position.owner == address(0)) revert Errors.InvalidPosition();

        // claim exited assets
        (uint256 leftTickets,, uint256 exitedAssets) = IVaultEnterExit(vault)
            .calculateExitedAssets(address(this), exitPositionTicket, timestamp, uint256(exitQueueIndex));
        // the exit request must be fully processed (1 ticket could be a rounding error)
        if (leftTickets > 1) revert Errors.ExitRequestNotProcessed();
        IVaultEnterExit(vault).claimExitedAssets(exitPositionTicket, timestamp, uint256(exitQueueIndex));

        // update position
        position.exitedAssets = SafeCast.toUint96(exitedAssets);

        // emit event
        emit ExitedAssetsProcessed(vault, msg.sender, exitPositionTicket, exitedAssets);
    }

    /// @inheritdoc IOsTokenVaultEscrow
    function claimExitedAssets(address vault, uint256 exitPositionTicket, uint256 osTokenShares)
        external
        override
        returns (uint256 claimedAssets)
    {
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
        if (position.osTokenShares != osTokenShares) {
            claimedAssets = Math.mulDiv(position.exitedAssets, osTokenShares, position.osTokenShares);

            // update position osTokenShares
            position.exitedAssets -= SafeCast.toUint96(claimedAssets);
            position.osTokenShares -= SafeCast.toUint128(osTokenShares);
            _positions[vault][exitPositionTicket] = position;
        } else {
            claimedAssets = position.exitedAssets;

            // remove position as it is fully processed
            delete _positions[vault][exitPositionTicket];
        }
        if (claimedAssets == 0) revert Errors.ExitRequestNotProcessed();

        // transfer assets
        _transferAssets(position.owner, claimedAssets);

        // emit event
        emit ExitedAssetsClaimed(msg.sender, vault, exitPositionTicket, osTokenShares, claimedAssets);
    }

    /// @inheritdoc IOsTokenVaultEscrow
    function liquidateOsToken(address vault, uint256 exitPositionTicket, uint256 osTokenShares, address receiver)
        external
        override
    {
        uint256 receivedAssets = _redeemOsToken(vault, exitPositionTicket, receiver, osTokenShares, true);
        emit OsTokenLiquidated(msg.sender, vault, exitPositionTicket, receiver, osTokenShares, receivedAssets);
    }

    /// @inheritdoc IOsTokenVaultEscrow
    function redeemOsToken(address vault, uint256 exitPositionTicket, uint256 osTokenShares, address receiver)
        external
        override
    {
        if (msg.sender != _osTokenConfig.redeemer()) revert Errors.AccessDenied();
        uint256 receivedAssets = _redeemOsToken(vault, exitPositionTicket, receiver, osTokenShares, false);
        emit OsTokenRedeemed(msg.sender, vault, exitPositionTicket, receiver, osTokenShares, receivedAssets);
    }

    /// @inheritdoc IOsTokenVaultEscrow
    function setAuthenticator(address newAuthenticator) public override onlyOwner {
        if (authenticator == newAuthenticator) revert Errors.ValueNotChanged();
        authenticator = newAuthenticator;
        emit AuthenticatorUpdated(newAuthenticator);
    }

    /// @inheritdoc IOsTokenVaultEscrow
    function updateLiqConfig(uint64 _liqThresholdPercent, uint256 _liqBonusPercent) public override onlyOwner {
        // validate liquidation threshold percent
        if (_liqThresholdPercent == 0 || _liqThresholdPercent >= _maxPercent) {
            revert Errors.InvalidLiqThresholdPercent();
        }

        // validate liquidation bonus percent
        if (
            _liqBonusPercent < _maxPercent
                || Math.mulDiv(_liqThresholdPercent, _liqBonusPercent, _maxPercent) > _maxPercent
        ) {
            revert Errors.InvalidLiqBonusPercent();
        }

        // update config
        liqThresholdPercent = _liqThresholdPercent;
        liqBonusPercent = _liqBonusPercent;

        // emit event
        emit LiqConfigUpdated(_liqThresholdPercent, _liqBonusPercent);
    }

    /**
     * @dev Internal function for redeeming osToken shares
     * @param vault The address of the vault
     * @param exitPositionTicket The position ticket of the exit queue
     * @param receiver The address of the receiver of the redeemed assets
     * @param osTokenShares The amount of osToken shares to redeem
     * @param isLiquidation Whether the redeem is a liquidation
     * @return receivedAssets The amount of assets received
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

        // calculate received assets
        if (isLiquidation) {
            receivedAssets =
                Math.mulDiv(_osTokenVaultController.convertToAssets(osTokenShares), liqBonusPercent, _maxPercent);
        } else {
            receivedAssets = _osTokenVaultController.convertToAssets(osTokenShares);
        }

        {
            // check whether received assets are valid
            if (receivedAssets > position.exitedAssets) {
                revert Errors.InvalidReceivedAssets();
            }

            if (isLiquidation) {
                // check health factor violation in case of liquidation
                uint256 mintedAssets = _osTokenVaultController.convertToAssets(position.osTokenShares);
                if (
                    Math.mulDiv(position.exitedAssets * _wad, liqThresholdPercent, mintedAssets * _maxPercent)
                        >= _hfLiqThreshold
                ) {
                    revert Errors.InvalidHealthFactor();
                }
            }
        }

        // reduce osToken supply
        _osTokenVaultController.burnShares(msg.sender, osTokenShares);

        // update position
        position.exitedAssets -= SafeCast.toUint96(receivedAssets);
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
