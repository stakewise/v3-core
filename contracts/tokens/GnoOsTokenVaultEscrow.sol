// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OsTokenVaultEscrow} from "./OsTokenVaultEscrow.sol";

/**
 * @title GnoOsTokenVaultEscrow
 * @author StakeWise
 * @notice Used for initiating assets exits from the vault without burning osToken on Gnosis
 */
contract GnoOsTokenVaultEscrow is OsTokenVaultEscrow {
    IERC20 private immutable _gnoToken;

    /**
     * @dev Constructor
     * @param osTokenVaultController The address of the OsTokenVaultController contract
     * @param osTokenConfig The address of the OsTokenConfig contract
     * @param initialOwner The address of the contract owner
     * @param _authenticator The address of the OsTokenVaultEscrowAuth contract
     * @param _liqThresholdPercent The liquidation threshold percent
     * @param _liqBonusPercent The liquidation bonus percent
     * @param gnoToken The address of the GNO token
     */
    constructor(
        address osTokenVaultController,
        address osTokenConfig,
        address initialOwner,
        address _authenticator,
        uint64 _liqThresholdPercent,
        uint256 _liqBonusPercent,
        address gnoToken
    )
        OsTokenVaultEscrow(
            osTokenVaultController,
            osTokenConfig,
            initialOwner,
            _authenticator,
            _liqThresholdPercent,
            _liqBonusPercent
        )
    {
        _gnoToken = IERC20(gnoToken);
    }

    /// @inheritdoc OsTokenVaultEscrow
    function _transferAssets(address receiver, uint256 assets) internal override {
        SafeERC20.safeTransfer(_gnoToken, receiver, assets);
    }
}
