// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IVaultEthStaking} from "../interfaces/IVaultEthStaking.sol";
import {IEthNodesManager} from "../interfaces/IEthNodesManager.sol";
import {NodesManager} from "./NodesManager.sol";

/**
 * @title EthNodesManager
 * @author StakeWise
 * @notice Implements Ethereum specific functionality for the NodesManager contract
 */
contract EthNodesManager is ReentrancyGuardUpgradeable, NodesManager, IEthNodesManager {
    /**
     * @dev Constructor
     * @param _vault The address of the vault for depositing bond assets
     * @param _keeper The address of the Keeper contract
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _vault, address _keeper) NodesManager(_vault, _keeper) {
        _disableInitializers();
    }

    /**
     * @dev Initializes the EthNodesManager contract
     * @param owner The address of the contract owner
     * @param _minBondAssets The minimum assets required for a deposit request
     * @param _exitPenaltyPercent The exit penalty percent in BPS
     * @param _ltvPercent The LTV percent in BPS
     */
    function initialize(address owner, uint256 _minBondAssets, uint16 _exitPenaltyPercent, uint16 _ltvPercent)
        external
        initializer
    {
        __ReentrancyGuard_init();
        __NodesManager_init(owner, _minBondAssets, _exitPenaltyPercent, _ltvPercent);
    }

    /// @inheritdoc IEthNodesManager
    function enterDepositQueue() external payable override returns (uint256 ticket) {
        return _enterDepositQueue(msg.value);
    }

    /// @inheritdoc NodesManager
    function _transferAssets(address receiver, uint256 assets) internal override nonReentrant {
        Address.sendValue(payable(receiver), assets);
    }

    /// @inheritdoc NodesManager
    function _depositToVault(uint256 assets) internal override returns (uint256 shares) {
        return IVaultEthStaking(vault).deposit{value: assets}(address(this), address(0));
    }
}
