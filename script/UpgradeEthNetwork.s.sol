// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {console} from "forge-std/console.sol";
import {IMetaVault} from "../contracts/interfaces/IMetaVault.sol";
import {IVaultVersion} from "../contracts/interfaces/IVaultVersion.sol";
import {IVaultsRegistry} from "../contracts/interfaces/IVaultsRegistry.sol";
import {EthOsTokenRedeemer} from "../contracts/tokens/EthOsTokenRedeemer.sol";
import {EthValidatorsChecker} from "../contracts/validators/EthValidatorsChecker.sol";
import {EthMetaVault} from "../contracts/vaults/ethereum/EthMetaVault.sol";
import {EthMetaVaultFactory} from "../contracts/vaults/ethereum/EthMetaVaultFactory.sol";
import {EthPrivMetaVault} from "../contracts/vaults/ethereum/EthPrivMetaVault.sol";
import {Network} from "./Network.sol";

contract UpgradeEthNetwork is Network {
    address public osTokenRedeemerOwner;
    address public validatorsRegistry;
    uint256 public osTokenRedeemerExitQueueUpdateDelay;

    address public validatorsChecker;
    address public osTokenRedeemer;

    address[] public vaultImpls;
    Factory[] public vaultFactories;

    function run() external {
        osTokenRedeemerOwner = vm.envAddress("OS_TOKEN_REDEEMER_OWNER");
        osTokenRedeemerExitQueueUpdateDelay = vm.envUint("OS_TOKEN_REDEEMER_EXIT_QUEUE_UPDATE_DELAY");
        validatorsRegistry = vm.envAddress("VALIDATORS_REGISTRY");
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address sender = vm.addr(privateKey);
        console.log("Deploying from: ", sender);

        Deployment memory deployment = getDeploymentData();

        vm.startBroadcast(privateKey);

        // Deploy common contracts
        validatorsChecker = address(
            new EthValidatorsChecker(
                validatorsRegistry,
                deployment.keeper,
                deployment.vaultsRegistry,
                deployment.depositDataRegistry,
                deployment.legacyPoolEscrow
            )
        );

        // Deploy OsToken redeemer
        osTokenRedeemer = address(
            new EthOsTokenRedeemer(
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
        EthMetaVault ethMetaVault = new EthMetaVault(metaVaultArgs);

        metaVaultArgs.exitingAssetsClaimDelay = PRIVATE_VAULT_EXITED_ASSETS_CLAIM_DELAY;
        EthPrivMetaVault ethPrivMetaVault = new EthPrivMetaVault(metaVaultArgs);

        vaultImpls.push(address(ethMetaVault));
        vaultImpls.push(address(ethPrivMetaVault));
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
