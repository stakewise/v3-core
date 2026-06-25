// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {console} from "forge-std/console.sol";
import {IEthErc20MetaVault} from "../contracts/interfaces/IEthErc20MetaVault.sol";
import {IEthMetaVault} from "../contracts/interfaces/IEthMetaVault.sol";
import {IVaultVersion} from "../contracts/interfaces/IVaultVersion.sol";
import {IVaultsRegistry} from "../contracts/interfaces/IVaultsRegistry.sol";
import {SubVaultsRegistry} from "../contracts/vaults/SubVaultsRegistry.sol";
import {SubVaultsRegistryFactory} from "../contracts/vaults/SubVaultsRegistryFactory.sol";
import {EthErc20MetaVault} from "../contracts/vaults/ethereum/EthErc20MetaVault.sol";
import {EthMetaVault} from "../contracts/vaults/ethereum/EthMetaVault.sol";
import {EthMetaVaultFactory} from "../contracts/vaults/ethereum/EthMetaVaultFactory.sol";
import {EthPrivErc20MetaVault} from "../contracts/vaults/ethereum/EthPrivErc20MetaVault.sol";
import {EthPrivMetaVault} from "../contracts/vaults/ethereum/EthPrivMetaVault.sol";
import {Network} from "./Network.sol";

contract UpgradeEthNetwork is Network {
    address public subVaultsRegistryFactory;

    address[] public vaultImpls;
    Factory[] public vaultFactories;

    function run() external {
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
        _deployFactories();
        vm.stopBroadcast();

        generateGovernorTxJson(vaultImpls, vaultFactories);
        generateUpgradesJson(vaultImpls);
        generateAddressesJson(vaultFactories, subVaultsRegistryFactory);
    }

    function _deployImplementations() internal {
        // constructors for implementations
        IEthMetaVault.EthMetaVaultConstructorArgs memory metaVaultArgs = _getEthMetaVaultConstructorArgs();
        IEthErc20MetaVault.EthErc20MetaVaultConstructorArgs memory erc20MetaVaultArgs =
            _getEthErc20MetaVaultConstructorArgs();

        // deploy meta vaults
        metaVaultArgs.exitingAssetsClaimDelay = PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY;
        EthMetaVault ethMetaVault = new EthMetaVault(metaVaultArgs);

        metaVaultArgs.exitingAssetsClaimDelay = PRIVATE_VAULT_EXITED_ASSETS_CLAIM_DELAY;
        EthPrivMetaVault ethPrivMetaVault = new EthPrivMetaVault(metaVaultArgs);

        // deploy ERC20 meta vaults
        erc20MetaVaultArgs.exitingAssetsClaimDelay = PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY;
        EthErc20MetaVault ethErc20MetaVault = new EthErc20MetaVault(erc20MetaVaultArgs);

        erc20MetaVaultArgs.exitingAssetsClaimDelay = PRIVATE_VAULT_EXITED_ASSETS_CLAIM_DELAY;
        EthPrivErc20MetaVault ethPrivErc20MetaVault = new EthPrivErc20MetaVault(erc20MetaVaultArgs);

        vaultImpls.push(address(ethMetaVault));
        vaultImpls.push(address(ethPrivMetaVault));
        vaultImpls.push(address(ethErc20MetaVault));
        vaultImpls.push(address(ethPrivErc20MetaVault));
    }

    function _deployFactories() internal {
        Deployment memory deployment = getDeploymentData();
        for (uint256 i = 0; i < vaultImpls.length; i++) {
            address vaultImpl = vaultImpls[i];
            bytes32 vaultId = IVaultVersion(vaultImpl).vaultId();

            address factory = address(new EthMetaVaultFactory(vaultImpl, IVaultsRegistry(deployment.vaultsRegistry)));
            if (vaultId == keccak256("EthMetaVault")) {
                vaultFactories.push(Factory({name: "MetaVaultFactory", factory: factory}));
            } else if (vaultId == keccak256("EthPrivMetaVault")) {
                vaultFactories.push(Factory({name: "PrivMetaVaultFactory", factory: factory}));
            } else if (vaultId == keccak256("EthErc20MetaVault")) {
                vaultFactories.push(Factory({name: "Erc20MetaVaultFactory", factory: factory}));
            } else if (vaultId == keccak256("EthPrivErc20MetaVault")) {
                vaultFactories.push(Factory({name: "PrivErc20MetaVaultFactory", factory: factory}));
            }
        }
    }

    function _getEthMetaVaultConstructorArgs() internal returns (IEthMetaVault.EthMetaVaultConstructorArgs memory) {
        Deployment memory deployment = getDeploymentData();
        return IEthMetaVault.EthMetaVaultConstructorArgs({
            keeper: deployment.keeper,
            vaultsRegistry: deployment.vaultsRegistry,
            osTokenVaultController: deployment.osTokenVaultController,
            osTokenConfig: deployment.osTokenConfig,
            osTokenVaultEscrow: deployment.osTokenVaultEscrow,
            subVaultsRegistryFactory: subVaultsRegistryFactory,
            exitingAssetsClaimDelay: PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY
        });
    }

    function _getEthErc20MetaVaultConstructorArgs()
        internal
        returns (IEthErc20MetaVault.EthErc20MetaVaultConstructorArgs memory)
    {
        Deployment memory deployment = getDeploymentData();
        return IEthErc20MetaVault.EthErc20MetaVaultConstructorArgs({
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
