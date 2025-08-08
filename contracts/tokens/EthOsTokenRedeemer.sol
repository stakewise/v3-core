// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IEthOsTokenRedeemer} from "../interfaces/IEthOsTokenRedeemer.sol";
import {OsTokenRedeemer} from "./OsTokenRedeemer.sol";

/**
 * @title EthOsTokenRedeemer
 * @author StakeWise
 * @notice This contract is used to redeem OsTokens for the underlying asset.
 */
contract EthOsTokenRedeemer is IEthOsTokenRedeemer, ReentrancyGuard, OsTokenRedeemer {
    /**
     * @dev Constructor
     * @param osToken_ The address of the OsToken contract
     * @param osTokenVaultController_ The address of the OsTokenVaultController contract
     * @param owner_ The address of the owner
     * @param positionsUpdateDelay_ The delay in seconds for positions updates
     * @param exitQueueUpdateDelay_ The delay in seconds for exit queue updates
     */
    constructor(
        address osToken_,
        address osTokenVaultController_,
        address owner_,
        uint256 positionsUpdateDelay_,
        uint256 exitQueueUpdateDelay_
    )
        ReentrancyGuard()
        OsTokenRedeemer(osToken_, osTokenVaultController_, owner_, positionsUpdateDelay_, exitQueueUpdateDelay_)
    {}

    /// @inheritdoc IEthOsTokenRedeemer
    function swapAssetsToOsTokenShares(address receiver) external payable override returns (uint256 osTokenShares) {
        return _swapAssetsToOsTokenShares(receiver, msg.value);
    }

    /// @inheritdoc OsTokenRedeemer
    function _availableAssets() internal view override returns (uint256) {
        return address(this).balance;
    }

    /// @inheritdoc OsTokenRedeemer
    function _transferAssets(address receiver, uint256 assets) internal override nonReentrant {
        return Address.sendValue(payable(receiver), assets);
    }

    /**
     * @dev Function for receiving redeemed assets.
     */
    receive() external payable {}
}
