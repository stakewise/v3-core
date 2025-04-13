// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IValidatorsRegistry} from "../interfaces/IValidatorsRegistry.sol";
import {IVaultsRegistry} from "../interfaces/IVaultsRegistry.sol";
import {IOsTokenVaultController} from "../interfaces/IOsTokenVaultController.sol";
import {IKeeper} from "../interfaces/IKeeper.sol";
import {KeeperValidators} from "./KeeperValidators.sol";
import {KeeperRewards} from "./KeeperRewards.sol";
import {KeeperOracles} from "./KeeperOracles.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title Keeper
 * @author StakeWise
 * @notice Defines the functionality for updating Vaults' rewards and approving validators registrations
 */
contract Keeper is KeeperOracles, KeeperRewards, KeeperValidators, IKeeper {
    bool private _initialized;

    /**
     * @dev Constructor
     * @param sharedMevEscrow The address of the shared MEV escrow contract
     * @param vaultsRegistry The address of the VaultsRegistry contract
     * @param osTokenVaultController The address of the OsTokenVaultController contract
     * @param _rewardsDelay The delay in seconds between rewards updates
     * @param maxAvgRewardPerSecond The maximum possible average reward per second
     * @param validatorsRegistry The address of the beacon chain validators registry contract
     */
    constructor(
        address sharedMevEscrow,
        IVaultsRegistry vaultsRegistry,
        IOsTokenVaultController osTokenVaultController,
        uint256 _rewardsDelay,
        uint256 maxAvgRewardPerSecond,
        IValidatorsRegistry validatorsRegistry
    )
        KeeperOracles()
        KeeperRewards(sharedMevEscrow, vaultsRegistry, osTokenVaultController, _rewardsDelay, maxAvgRewardPerSecond)
        KeeperValidators(validatorsRegistry)
    {}

    /// @inheritdoc IKeeper
    function initialize(address _owner) external override onlyOwner {
        if (_owner == address(0)) revert Errors.ZeroAddress();
        if (_initialized) revert Errors.AccessDenied();

        // transfer ownership
        _transferOwnership(_owner);
        _initialized = true;
    }
}
