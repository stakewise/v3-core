// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IVaultEthStaking} from "../interfaces/IVaultEthStaking.sol";
import {IEthNodesManager} from "../interfaces/IEthNodesManager.sol";
import {NodesManager} from "./NodesManager.sol";

/**
 * @title EthNodesManager
 * @author StakeWise
 * @notice Implements Ethereum specific functionality for the NodesManager contract
 */
contract EthNodesManager is NodesManager, IEthNodesManager {
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
     * @param _ltvPercent The LTV percent in BPS
     */
    function initialize(address owner, uint256 _minBondAssets, uint16 _ltvPercent) external initializer {
        __NodesManager_init(owner, _minBondAssets, _ltvPercent);
    }

    /// @inheritdoc IEthNodesManager
    function deposit() external payable override returns (uint256 shares) {
        return _deposit(msg.value);
    }

    /// @inheritdoc NodesManager
    function _depositToVault(uint256 assets) internal override returns (uint256 shares) {
        return IVaultEthStaking(vault).deposit{value: assets}(address(this), address(0));
    }
}
