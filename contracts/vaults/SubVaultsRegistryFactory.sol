// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ISubVaultsRegistryFactory} from "../interfaces/ISubVaultsRegistryFactory.sol";
import {IVaultsRegistry} from "../interfaces/IVaultsRegistry.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title SubVaultsRegistryFactory
 * @author StakeWise
 * @notice Factory for deploying SubVaultsRegistry contracts
 */
contract SubVaultsRegistryFactory is ISubVaultsRegistryFactory {
    IVaultsRegistry internal immutable _vaultsRegistry;

    /// @inheritdoc ISubVaultsRegistryFactory
    address public immutable override implementation;

    /**
     * @dev Constructor
     * @param _implementation The implementation address of SubVaultsRegistry
     * @param vaultsRegistry The address of the VaultsRegistry contract
     */
    constructor(address _implementation, IVaultsRegistry vaultsRegistry) {
        implementation = _implementation;
        _vaultsRegistry = vaultsRegistry;
    }

    /// @inheritdoc ISubVaultsRegistryFactory
    function createSubVaultsRegistry() external override returns (address) {
        if (!_vaultsRegistry.vaults(msg.sender)) {
            revert Errors.InvalidVault();
        }
        address subVaultsRegistry = address(new ERC1967Proxy(implementation, ""));
        emit SubVaultsRegistryCreated(msg.sender, subVaultsRegistry);
        return subVaultsRegistry;
    }
}
