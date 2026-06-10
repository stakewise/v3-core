// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {console} from "forge-std/console.sol";
import {IGnoMetaVault} from "../contracts/interfaces/IGnoMetaVault.sol";
import {IVaultsRegistry} from "../contracts/interfaces/IVaultsRegistry.sol";
import {SubVaultsRegistry} from "../contracts/vaults/SubVaultsRegistry.sol";
import {SubVaultsRegistryFactory} from "../contracts/vaults/SubVaultsRegistryFactory.sol";
import {GnoMetaVault} from "../contracts/vaults/gnosis/GnoMetaVault.sol";
import {Network} from "./Network.sol";

contract UpgradeGnoNetwork is Network {
    address public gnoToken;
    address public subVaultsRegistryFactory;

    address[] public vaultImpls;

    function run() external {
        gnoToken = vm.envAddress("GNO_TOKEN");
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address sender = vm.addr(privateKey);
        console.log("Deploying from: ", sender);

        Deployment memory deployment = getDeploymentData();

        vm.startBroadcast(privateKey);

        // Deploy SubVaultsRegistryFactory with the new SubVaultsRegistry implementation
        address subVaultsRegistryImpl = address(
            new SubVaultsRegistry(
                deployment.curatorsRegistry,
                deployment.vaultsRegistry,
                deployment.keeper,
                deployment.osTokenVaultController,
                deployment.osTokenConfig
            )
        );
        subVaultsRegistryFactory =
            address(new SubVaultsRegistryFactory(subVaultsRegistryImpl, IVaultsRegistry(deployment.vaultsRegistry)));

        _deployImplementations();
        vm.stopBroadcast();

        // no new meta vault factory is deployed, the existing one gets removed
        Factory[] memory vaultFactories = new Factory[](0);
        generateGovernorTxJson(vaultImpls, vaultFactories);
        generateUpgradesJson(vaultImpls);
        generateAddressesJson(vaultFactories, subVaultsRegistryFactory);
    }

    function _deployImplementations() internal {
        // constructors for implementations
        IGnoMetaVault.GnoMetaVaultConstructorArgs memory metaVaultArgs = _getGnoMetaVaultConstructorArgs();

        // deploy meta vaults
        metaVaultArgs.exitingAssetsClaimDelay = PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY;
        GnoMetaVault gnoMetaVault = new GnoMetaVault(gnoToken, metaVaultArgs);

        vaultImpls.push(address(gnoMetaVault));
    }

    function _getGnoMetaVaultConstructorArgs() internal returns (IGnoMetaVault.GnoMetaVaultConstructorArgs memory) {
        Deployment memory deployment = getDeploymentData();
        return IGnoMetaVault.GnoMetaVaultConstructorArgs({
            keeper: deployment.keeper,
            vaultsRegistry: deployment.vaultsRegistry,
            osTokenVaultController: deployment.osTokenVaultController,
            osTokenConfig: deployment.osTokenConfig,
            osTokenVaultEscrow: deployment.osTokenVaultEscrow,
            subVaultsRegistryFactory: subVaultsRegistryFactory,
            exitingAssetsClaimDelay: PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY
        });
    }
}
