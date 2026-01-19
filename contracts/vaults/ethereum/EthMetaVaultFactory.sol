// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IEthMetaVaultFactory} from "../../interfaces/IEthMetaVaultFactory.sol";
import {IEthMetaVault} from "../../interfaces/IEthMetaVault.sol";
import {IVaultsRegistry} from "../../interfaces/IVaultsRegistry.sol";
import {Errors} from "../../libraries/Errors.sol";

/**
 * @title EthMetaVaultFactory
 * @author StakeWise
 * @notice Factory for deploying Ethereum meta Vaults
 */
contract EthMetaVaultFactory is IEthMetaVaultFactory {
    IVaultsRegistry internal immutable _vaultsRegistry;

    /// @inheritdoc IEthMetaVaultFactory
    address public immutable override implementation;

    /// @inheritdoc IEthMetaVaultFactory
    address public override vaultAdmin;

    /**
     * @dev Constructor
     * @param _implementation The implementation address of Vault
     * @param vaultsRegistry The address of the VaultsRegistry contract
     */
    constructor(address _implementation, IVaultsRegistry vaultsRegistry) {
        implementation = _implementation;
        _vaultsRegistry = vaultsRegistry;
    }

    /// @inheritdoc IEthMetaVaultFactory
    function createVault(bytes calldata params) external payable override returns (address vault) {
        // create vault
        vault = address(new ERC1967Proxy(implementation, ""));

        // set admin so that it can be initialized in the Vault
        vaultAdmin = msg.sender;

        // initialize Vault
        IEthMetaVault(vault).initialize{value: msg.value}(params);

        // cleanup admin
        delete vaultAdmin;

        // add vault to the registry
        _vaultsRegistry.addVault(vault);

        // emit event
        emit MetaVaultCreated(msg.sender, vault, params);
    }
}
