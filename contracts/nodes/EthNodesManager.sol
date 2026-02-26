// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IVaultEthStaking} from "../interfaces/IVaultEthStaking.sol";
import {IEthNodesManager} from "../interfaces/IEthNodesManager.sol";
import {Errors} from "../libraries/Errors.sol";
import {NodesManager} from "./NodesManager.sol";

/**
 * @title EthNodesManager
 * @author StakeWise
 * @notice Implements Ethereum specific functionality for the NodesManager contract
 */
contract EthNodesManager is NodesManager, IEthNodesManager {
    /**
     * @dev Constructor
     * @param vault_ The address of the vault
     * @param _keeper The address of the Keeper contract
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _vault, address _keeper) NodesManager(_vault, _keeper) {
        _disableInitializers();
    }

    /**
     * @dev Initializes the EthNodesManager contract
     * @param owner The address of the contract owner
     * @param _minDepositAssets The minimum deposit assets
     * @param _minBalancePercent The minimum balance percent in BPS
     * @param _stateUpdateDelay The delay in seconds between state updates
     */
    function initialize(address owner, uint256 _minDepositAssets, uint16 _minBalancePercent, uint256 _stateUpdateDelay)
        external
        initializer
    {
        __NodesManager_init(owner, _minDepositAssets, _minBalancePercent, _stateUpdateDelay);
    }

    /// @inheritdoc IEthNodesManager
    function deposit() external payable override returns (uint256 shares) {
        return _deposit(msg.value);
    }

    /// @inheritdoc NodesManager
    function _depositToVault(uint256 assets) internal override returns (uint256 shares) {
        return IVaultEthStaking(vault).deposit{value: assets}(address(this), address(0));
    }

    /// @inheritdoc NodesManager
    function _transferAssets(address receiver, uint256 assets) internal override {
        Address.sendValue(payable(receiver), assets);
    }

    /// @inheritdoc NodesManager
    function _donateAssets(uint256 assets) internal override {
        IVaultEthStaking(vault).donateAssets{value: assets}();
    }

    receive() external payable {
        if (msg.sender != vault) revert Errors.AccessDenied();
    }
}
