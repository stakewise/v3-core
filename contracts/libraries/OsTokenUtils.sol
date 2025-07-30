// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IOsTokenConfig} from "../interfaces/IOsTokenConfig.sol";
import {IOsTokenVaultController} from "../interfaces/IOsTokenVaultController.sol";
import {Errors} from "./Errors.sol";

/**
 * @title OsTokenUtils
 * @author StakeWise
 * @notice Includes functionality for handling osToken redemptions
 */
library OsTokenUtils {
    uint256 private constant _wad = 1e18;
    uint256 private constant _hfLiqThreshold = 1e18;
    uint256 private constant _maxPercent = 1e18;
    uint256 private constant _disabledLiqThreshold = type(uint64).max;

    /**
     * @dev Struct for storing redemption data
     * @param mintedAssets The amount of minted assets
     * @param depositedAssets The amount of deposited assets
     * @param redeemedOsTokenShares The amount of redeemed osToken shares
     * @param availableAssets The amount of available assets
     * @param isLiquidation Whether the redemption is a liquidation
     */
    struct RedemptionData {
        uint256 mintedAssets;
        uint256 depositedAssets;
        uint256 redeemedOsTokenShares;
        uint256 availableAssets;
        bool isLiquidation;
    }

    /**
     * @dev Calculates the amount of received assets during osToken redemption
     * @param osTokenConfig The address of the osToken config contract
     * @param osTokenVaultController The address of the osToken vault controller contract
     * @param data The redemption data
     * @return receivedAssets The amount of received assets
     */
    function calculateReceivedAssets(
        IOsTokenConfig osTokenConfig,
        IOsTokenVaultController osTokenVaultController,
        RedemptionData memory data
    ) external view returns (uint256 receivedAssets) {
        // SLOAD to memory
        IOsTokenConfig.Config memory config = osTokenConfig.getConfig(address(this));
        if (data.isLiquidation && config.liqThresholdPercent == _disabledLiqThreshold) {
            revert Errors.LiquidationDisabled();
        }

        // calculate received assets
        if (data.isLiquidation) {
            receivedAssets = Math.mulDiv(
                osTokenVaultController.convertToAssets(data.redeemedOsTokenShares), config.liqBonusPercent, _maxPercent
            );
        } else {
            receivedAssets = osTokenVaultController.convertToAssets(data.redeemedOsTokenShares);
        }

        {
            // check whether received assets are valid
            if (receivedAssets > data.depositedAssets || receivedAssets > data.availableAssets) {
                revert Errors.InvalidReceivedAssets();
            }

            // check health factor violation in case of liquidation
            if (
                data.isLiquidation
                    && Math.mulDiv(data.depositedAssets * _wad, config.liqThresholdPercent, data.mintedAssets * _maxPercent)
                        >= _hfLiqThreshold
            ) {
                revert Errors.InvalidHealthFactor();
            }

            return receivedAssets;
        }
    }
}
