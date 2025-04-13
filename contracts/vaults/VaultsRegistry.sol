// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IVaultsRegistry} from "../interfaces/IVaultsRegistry.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title VaultsRegistry
 * @author StakeWise
 * @notice Defines the registry functionality that keeps track of Vaults, Factories and Vault upgrades
 */
contract VaultsRegistry is Ownable2Step, IVaultsRegistry {
    /// @inheritdoc IVaultsRegistry
    mapping(address => bool) public override vaults;

    /// @inheritdoc IVaultsRegistry
    mapping(address => bool) public override factories;

    /// @inheritdoc IVaultsRegistry
    mapping(address => bool) public override vaultImpls;

    bool private _initialized;

    /**
     * @dev Constructor
     */
    constructor() Ownable(msg.sender) {}

    /// @inheritdoc IVaultsRegistry
    function addVault(address vault) external override {
        if (!factories[msg.sender] && msg.sender != owner()) revert Errors.AccessDenied();

        vaults[vault] = true;
        emit VaultAdded(msg.sender, vault);
    }

    /// @inheritdoc IVaultsRegistry
    function addVaultImpl(address newImpl) external override onlyOwner {
        if (vaultImpls[newImpl]) revert Errors.AlreadyAdded();
        vaultImpls[newImpl] = true;
        emit VaultImplAdded(newImpl);
    }

    /// @inheritdoc IVaultsRegistry
    function removeVaultImpl(address impl) external override onlyOwner {
        if (!vaultImpls[impl]) revert Errors.AlreadyRemoved();
        vaultImpls[impl] = false;
        emit VaultImplRemoved(impl);
    }

    /// @inheritdoc IVaultsRegistry
    function addFactory(address factory) external override onlyOwner {
        if (factories[factory]) revert Errors.AlreadyAdded();
        factories[factory] = true;
        emit FactoryAdded(factory);
    }

    /// @inheritdoc IVaultsRegistry
    function removeFactory(address factory) external override onlyOwner {
        if (!factories[factory]) revert Errors.AlreadyRemoved();
        factories[factory] = false;
        emit FactoryRemoved(factory);
    }

    /// @inheritdoc IVaultsRegistry
    function initialize(address _owner) external override onlyOwner {
        if (_owner == address(0)) revert Errors.ZeroAddress();
        if (_initialized) revert Errors.AccessDenied();

        // transfer ownership
        _transferOwnership(_owner);
        _initialized = true;
    }
}
