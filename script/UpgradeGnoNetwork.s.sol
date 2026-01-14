// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IMetaVault} from "../contracts/interfaces/IMetaVault.sol";
import {IVaultVersion} from "../contracts/interfaces/IVaultVersion.sol";
import {IVaultsRegistry} from "../contracts/interfaces/IVaultsRegistry.sol";
import {GnoOsTokenRedeemer} from "../contracts/tokens/GnoOsTokenRedeemer.sol";
import {GnoValidatorsChecker} from "../contracts/validators/GnoValidatorsChecker.sol";
import {GnoMetaVault} from "../contracts/vaults/gnosis/GnoMetaVault.sol";
import {GnoMetaVaultFactory} from "../contracts/vaults/gnosis/GnoMetaVaultFactory.sol";
import {GnoPrivMetaVault} from "../contracts/vaults/gnosis/GnoPrivMetaVault.sol";
import {Network} from "./Network.sol";
import {console} from "forge-std/console.sol";

contract UpgradeGnoNetwork is Network {
    address public osTokenRedeemerOwner;
    address public validatorsRegistry;
    address public gnoToken;
    uint256 public osTokenRedeemerExitQueueUpdateDelay;

    address public validatorsChecker;
    address public osTokenRedeemer;

    address[] public vaultImpls;
    Factory[] public vaultFactories;

    function run() external {
        osTokenRedeemerOwner = vm.envAddress("OS_TOKEN_REDEEMER_OWNER");
        osTokenRedeemerExitQueueUpdateDelay = vm.envUint("OS_TOKEN_REDEEMER_EXIT_QUEUE_UPDATE_DELAY");
        validatorsRegistry = vm.envAddress("VALIDATORS_REGISTRY");
        gnoToken = vm.envAddress("GNO_TOKEN");
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address sender = vm.addr(privateKey);
        console.log("Deploying from: ", sender);

        Deployment memory deployment = getDeploymentData();

        vm.startBroadcast(privateKey);

        // Deploy common contracts
        validatorsChecker = address(
            new GnoValidatorsChecker(
                validatorsRegistry,
                deployment.keeper,
                deployment.vaultsRegistry,
                deployment.depositDataRegistry,
                deployment.legacyPoolEscrow,
                gnoToken
            )
        );

        // Deploy OsToken redeemer
        osTokenRedeemer = address(
            new GnoOsTokenRedeemer(
                gnoToken,
                deployment.vaultsRegistry,
                deployment.osToken,
                deployment.osTokenVaultController,
                osTokenRedeemerOwner,
                osTokenRedeemerExitQueueUpdateDelay
            )
        );

        _deployImplementations();
        _deployFactories();
        vm.stopBroadcast();

        generateGovernorTxJson(vaultImpls, vaultFactories, osTokenRedeemer);
        generateUpgradesJson(vaultImpls);
        generateAddressesJson(vaultFactories, validatorsChecker, osTokenRedeemer);
    }

    function _deployImplementations() internal {
        // constructors for implementations
        IMetaVault.MetaVaultConstructorArgs memory metaVaultArgs = _getMetaVaultConstructorArgs();

        // deploy meta vaults
        metaVaultArgs.exitingAssetsClaimDelay = PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY;
        GnoMetaVault gnoMetaVault = new GnoMetaVault(gnoToken, metaVaultArgs);

        metaVaultArgs.exitingAssetsClaimDelay = PRIVATE_VAULT_EXITED_ASSETS_CLAIM_DELAY;
        GnoPrivMetaVault gnoPrivMetaVault = new GnoPrivMetaVault(gnoToken, metaVaultArgs);

        vaultImpls.push(address(gnoMetaVault));
        vaultImpls.push(address(gnoPrivMetaVault));
    }

    function _deployFactories() internal {
        Deployment memory deployment = getDeploymentData();
        for (uint256 i = 0; i < vaultImpls.length; i++) {
            address vaultImpl = vaultImpls[i];
            bytes32 vaultId = IVaultVersion(vaultImpl).vaultId();

            address factory =
                address(new GnoMetaVaultFactory(vaultImpl, IVaultsRegistry(deployment.vaultsRegistry), gnoToken));
            if (vaultId == keccak256("GnoMetaVault")) {
                vaultFactories.push(Factory({name: "MetaVaultFactory", factory: factory}));
            } else if (vaultId == keccak256("GnoPrivMetaVault")) {
                vaultFactories.push(Factory({name: "PrivMetaVaultFactory", factory: factory}));
            }
        }
    }

    function _getMetaVaultConstructorArgs() internal returns (IMetaVault.MetaVaultConstructorArgs memory) {
        Deployment memory deployment = getDeploymentData();
        return IMetaVault.MetaVaultConstructorArgs({
            keeper: deployment.keeper,
            vaultsRegistry: deployment.vaultsRegistry,
            osTokenVaultController: deployment.osTokenVaultController,
            osTokenConfig: deployment.osTokenConfig,
            osTokenVaultEscrow: deployment.osTokenVaultEscrow,
            curatorsRegistry: deployment.curatorsRegistry,
            exitingAssetsClaimDelay: PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY
        });
    }
}
