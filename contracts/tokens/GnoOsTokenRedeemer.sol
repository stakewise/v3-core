// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IGnoOsTokenRedeemer} from "../interfaces/IGnoOsTokenRedeemer.sol";
import {OsTokenRedeemer} from "./OsTokenRedeemer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title GnoOsTokenRedeemer
 * @author StakeWise
 * @notice This contract is used to redeem OsTokens for the underlying asset.
 */
contract GnoOsTokenRedeemer is IGnoOsTokenRedeemer, OsTokenRedeemer {
    IERC20 private immutable _gnoToken;

    /**
     * @dev Constructor
     * @param gnoToken_ The address of the GNO token contract
     * @param vaultsRegistry_ The address of the VaultsRegistry contract
     * @param osToken_ The address of the OsToken contract
     * @param osTokenVaultController_ The address of the OsTokenVaultController contract
     * @param owner_ The address of the owner
     * @param exitQueueUpdateDelay_ The delay in seconds for exit queue updates
     */
    constructor(
        address gnoToken_,
        address vaultsRegistry_,
        address osToken_,
        address osTokenVaultController_,
        address owner_,
        uint256 exitQueueUpdateDelay_
    ) OsTokenRedeemer(vaultsRegistry_, osToken_, osTokenVaultController_, owner_, exitQueueUpdateDelay_) {
        _gnoToken = IERC20(gnoToken_);
    }

    /// @inheritdoc IGnoOsTokenRedeemer
    function permitGnoToken(uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external override {
        try IERC20Permit(address(_gnoToken)).permit(msg.sender, address(this), amount, deadline, v, r, s) {} catch {}
    }

    /// @inheritdoc IGnoOsTokenRedeemer
    function swapAssetsToOsTokenShares(address receiver, uint256 assets)
        external
        override
        returns (uint256 osTokenShares)
    {
        SafeERC20.safeTransferFrom(_gnoToken, msg.sender, address(this), assets);
        return _swapAssetsToOsTokenShares(receiver, assets);
    }

    /// @inheritdoc OsTokenRedeemer
    function _getAssets(address account) internal view override returns (uint256) {
        return _gnoToken.balanceOf(account);
    }

    /// @inheritdoc OsTokenRedeemer
    function _transferAssets(address receiver, uint256 assets) internal override {
        SafeERC20.safeTransfer(_gnoToken, receiver, assets);
    }
}
