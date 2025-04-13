// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Errors} from "../libraries/Errors.sol";
import {OsTokenVaultEscrow} from "./OsTokenVaultEscrow.sol";

/**
 * @title EthOsTokenVaultEscrow
 * @author StakeWise
 * @notice Used for initiating assets exits from the vault without burning osToken on Ethereum
 */
contract EthOsTokenVaultEscrow is ReentrancyGuard, OsTokenVaultEscrow {
    /**
     * @notice Event emitted on assets received by the escrow
     * @param sender The address of the sender
     * @param value The amount of assets received
     */
    event AssetsReceived(address indexed sender, uint256 value);

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
    )
        ReentrancyGuard()
        OsTokenVaultEscrow(
            osTokenVaultController,
            osTokenConfig,
            initialOwner,
            _authenticator,
            _liqThresholdPercent,
            _liqBonusPercent
        )
    {}

    /**
     * @dev Function for receiving assets from the vault
     */
    receive() external payable {
        emit AssetsReceived(msg.sender, msg.value);
    }

    /// @inheritdoc OsTokenVaultEscrow
    function _transferAssets(address receiver, uint256 assets) internal override nonReentrant {
        return Address.sendValue(payable(receiver), assets);
    }
}
