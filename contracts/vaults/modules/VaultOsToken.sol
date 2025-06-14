// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IOsTokenVaultController} from "../../interfaces/IOsTokenVaultController.sol";
import {IOsTokenConfig} from "../../interfaces/IOsTokenConfig.sol";
import {IVaultOsToken} from "../../interfaces/IVaultOsToken.sol";
import {IOsTokenVaultEscrow} from "../../interfaces/IOsTokenVaultEscrow.sol";
import {Errors} from "../../libraries/Errors.sol";
import {VaultImmutables} from "./VaultImmutables.sol";
import {VaultEnterExit, IVaultEnterExit} from "./VaultEnterExit.sol";
import {VaultState} from "./VaultState.sol";
import {OsTokenUtils} from "../../libraries/OsTokenUtils.sol";

/**
 * @title VaultOsToken
 * @author StakeWise
 * @notice Defines the functionality for minting OsToken
 */
abstract contract VaultOsToken is VaultImmutables, VaultState, VaultEnterExit, IVaultOsToken {
    uint256 private constant _maxPercent = 1e18;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IOsTokenVaultController private immutable _osTokenVaultController;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IOsTokenConfig private immutable _osTokenConfig;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IOsTokenVaultEscrow private immutable _osTokenVaultEscrow;

    mapping(address => OsTokenPosition) private _positions;

    /**
     * @dev Constructor
     * @dev Since the immutable variable value is stored in the bytecode,
     *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
     * @param osTokenVaultController The address of the OsTokenVaultController contract
     * @param osTokenConfig The address of the OsTokenConfig contract
     * @param osTokenVaultEscrow The address of the OsTokenVaultEscrow contract
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address osTokenVaultController, address osTokenConfig, address osTokenVaultEscrow) {
        _osTokenVaultController = IOsTokenVaultController(osTokenVaultController);
        _osTokenConfig = IOsTokenConfig(osTokenConfig);
        _osTokenVaultEscrow = IOsTokenVaultEscrow(osTokenVaultEscrow);
    }

    /// @inheritdoc IVaultOsToken
    function osTokenPositions(address user) public view override returns (uint128 shares) {
        OsTokenPosition memory position = _positions[user];
        if (position.shares != 0) _syncPositionFee(position);
        return position.shares;
    }

    /// @inheritdoc IVaultOsToken
    function mintOsToken(address receiver, uint256 osTokenShares, address referrer)
        public
        virtual
        override
        returns (uint256 assets)
    {
        return _mintOsToken(msg.sender, receiver, osTokenShares, referrer);
    }

    /// @inheritdoc IVaultOsToken
    function burnOsToken(uint128 osTokenShares) external override returns (uint256 assets) {
        // burn osToken shares
        assets = _osTokenVaultController.burnShares(msg.sender, osTokenShares);

        // fetch user position
        OsTokenPosition memory position = _positions[msg.sender];
        if (position.shares == 0) revert Errors.InvalidPosition();
        _syncPositionFee(position);

        // update osToken position
        position.shares -= osTokenShares;
        _positions[msg.sender] = position;

        // emit event
        emit OsTokenBurned(msg.sender, assets, osTokenShares);
    }

    /// @inheritdoc IVaultOsToken
    function liquidateOsToken(uint256 osTokenShares, address owner, address receiver) external override {
        (uint256 burnedShares, uint256 receivedAssets) = _redeemOsToken(owner, receiver, osTokenShares, true);
        emit OsTokenLiquidated(msg.sender, owner, receiver, osTokenShares, burnedShares, receivedAssets);
    }

    /// @inheritdoc IVaultOsToken
    function redeemOsToken(uint256 osTokenShares, address owner, address receiver) external override {
        if (msg.sender != _osTokenConfig.redeemer()) revert Errors.AccessDenied();
        (uint256 burnedShares, uint256 receivedAssets) = _redeemOsToken(owner, receiver, osTokenShares, false);
        emit OsTokenRedeemed(msg.sender, owner, receiver, osTokenShares, burnedShares, receivedAssets);
    }

    /// @inheritdoc IVaultOsToken
    function transferOsTokenPositionToEscrow(uint256 osTokenShares)
        external
        override
        returns (uint256 positionTicket)
    {
        // check whether vault assets are up to date
        _checkHarvested();

        // fetch user osToken position
        OsTokenPosition memory position = _positions[msg.sender];
        if (position.shares == 0) revert Errors.InvalidPosition();

        // sync accumulated fee
        _syncPositionFee(position);
        if (position.shares < osTokenShares) revert Errors.InvalidShares();

        // calculate shares to enter the exit queue
        uint256 exitShares = _balances[msg.sender];
        if (position.shares != osTokenShares) {
            // calculate exit shares
            exitShares = Math.mulDiv(exitShares, osTokenShares, position.shares);
            // update osToken position
            unchecked {
                // cannot underflow because position.shares >= osTokenShares
                position.shares -= SafeCast.toUint128(osTokenShares);
            }
            _positions[msg.sender] = position;
        } else {
            // all the assets are sent to the exit queue, remove position
            delete _positions[msg.sender];
        }

        // enter the exit queue
        positionTicket = super.enterExitQueue(exitShares, address(_osTokenVaultEscrow));

        // transfer to escrow
        _osTokenVaultEscrow.register(msg.sender, positionTicket, osTokenShares, position.cumulativeFeePerShare);
    }

    /// @inheritdoc IVaultEnterExit
    function enterExitQueue(uint256 shares, address receiver)
        public
        virtual
        override(IVaultEnterExit, VaultEnterExit)
        returns (uint256 positionTicket)
    {
        positionTicket = super.enterExitQueue(shares, receiver);
        _checkOsTokenPosition(msg.sender);
    }

    /**
     * @dev Internal function for minting osToken shares
     * @param owner The owner of the osToken position
     * @param receiver The receiver of the osToken shares
     * @param osTokenShares The amount of osToken shares to mint
     * @param referrer The address of the referrer
     * @return assets The amount of assets minted
     */
    function _mintOsToken(address owner, address receiver, uint256 osTokenShares, address referrer)
        internal
        returns (uint256 assets)
    {
        _checkCollateralized();
        _checkHarvested();

        // fetch user position
        OsTokenPosition memory position = _positions[owner];
        if (position.shares != 0) {
            _syncPositionFee(position);
        } else {
            position.cumulativeFeePerShare = SafeCast.toUint128(_osTokenVaultController.cumulativeFeePerShare());
        }

        // calculate max osToken shares that user can mint
        uint256 userMaxOsTokenShares = _calcMaxOsTokenShares(convertToAssets(_balances[owner]));
        if (osTokenShares == type(uint256).max) {
            if (userMaxOsTokenShares <= position.shares) {
                return 0;
            }
            // calculate max OsToken shares that can be minted
            unchecked {
                // cannot underflow because position.shares < userMaxOsTokenShares
                osTokenShares = userMaxOsTokenShares - position.shares;
            }
        }

        // mint osToken shares to the receiver
        assets = _osTokenVaultController.mintShares(receiver, osTokenShares);

        // add minted shares to the position
        position.shares += SafeCast.toUint128(osTokenShares);

        // calculate and validate LTV
        if (userMaxOsTokenShares < position.shares) {
            revert Errors.LowLtv();
        }

        // update state
        _positions[owner] = position;

        // emit event
        emit OsTokenMinted(owner, receiver, assets, osTokenShares, referrer);
    }

    /**
     * @dev Internal function for redeeming and liquidating osToken shares
     * @param owner The minter of the osToken shares
     * @param receiver The receiver of the assets
     * @param osTokenShares The amount of osToken shares to redeem or liquidate
     * @param isLiquidation Whether the liquidation or redemption is being performed
     * @return burnedShares The amount of shares burned
     * @return receivedAssets The amount of assets received
     */
    function _redeemOsToken(address owner, address receiver, uint256 osTokenShares, bool isLiquidation)
        private
        returns (uint256 burnedShares, uint256 receivedAssets)
    {
        if (receiver == address(0)) revert Errors.ZeroAddress();
        _checkHarvested();

        // update osToken state for gas efficiency
        _osTokenVaultController.updateState();

        // fetch user position
        OsTokenPosition memory position = _positions[owner];
        if (position.shares == 0) revert Errors.InvalidPosition();
        _syncPositionFee(position);

        // calculate received assets
        receivedAssets = OsTokenUtils.calculateReceivedAssets(
            _osTokenConfig,
            _osTokenVaultController,
            OsTokenUtils.RedemptionData({
                mintedAssets: _osTokenVaultController.convertToAssets(position.shares),
                depositedAssets: convertToAssets(_balances[owner]),
                redeemedOsTokenShares: osTokenShares,
                availableAssets: withdrawableAssets(),
                isLiquidation: isLiquidation
            })
        );

        // reduce osToken supply
        _osTokenVaultController.burnShares(msg.sender, osTokenShares);

        // update osToken position
        position.shares -= SafeCast.toUint128(osTokenShares);
        _positions[owner] = position;

        burnedShares = convertToShares(receivedAssets);

        // update total assets
        unchecked {
            _totalAssets -= SafeCast.toUint128(receivedAssets);
        }

        // burn owner shares
        _burnShares(owner, burnedShares);

        // transfer assets to the receiver
        _transferVaultAssets(receiver, receivedAssets);
    }

    /**
     * @dev Internal function for syncing the osToken fee
     * @param position The position to sync the fee for
     */
    function _syncPositionFee(OsTokenPosition memory position) private view {
        // fetch current cumulative fee per share
        uint256 cumulativeFeePerShare = _osTokenVaultController.cumulativeFeePerShare();

        // check whether fee is already up to date
        if (cumulativeFeePerShare == position.cumulativeFeePerShare) return;

        // add treasury fee to the position
        position.shares =
            SafeCast.toUint128(Math.mulDiv(position.shares, cumulativeFeePerShare, position.cumulativeFeePerShare));
        position.cumulativeFeePerShare = SafeCast.toUint128(cumulativeFeePerShare);
    }

    /**
     * @notice Internal function for checking position validity. Reverts if it is invalid.
     * @param user The address of the user
     */
    function _checkOsTokenPosition(address user) internal view {
        // fetch user position
        OsTokenPosition memory position = _positions[user];
        if (position.shares == 0) return;

        // check whether vault assets are up to date
        _checkHarvested();

        // sync fee
        _syncPositionFee(position);

        // calculate and validate position LTV
        if (_calcMaxOsTokenShares(convertToAssets(_balances[user])) < position.shares) {
            revert Errors.LowLtv();
        }
    }

    /**
     * @dev Internal function for calculating the maximum amount of osToken shares that can be minted
     * @param assets The amount of assets to convert to osToken shares
     * @return maxOsTokenShares The maximum amount of osToken shares that can be minted
     */
    function _calcMaxOsTokenShares(uint256 assets) internal view returns (uint256) {
        uint256 maxOsTokenAssets = Math.mulDiv(assets, _osTokenConfig.getConfig(address(this)).ltvPercent, _maxPercent);
        return _osTokenVaultController.convertToShares(maxOsTokenAssets);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
