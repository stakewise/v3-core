// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {console} from "forge-std/console.sol";
import {IGnoVault} from "../contracts/interfaces/IGnoVault.sol";
import {IGnoErc20Vault} from "../contracts/interfaces/IGnoErc20Vault.sol";
import {IVaultsRegistry} from "../contracts/interfaces/IVaultsRegistry.sol";
import {IVaultVersion} from "../contracts/interfaces/IVaultVersion.sol";
import {ConsolidationsChecker} from "../contracts/validators/ConsolidationsChecker.sol";
import {GnoValidatorsChecker} from "../contracts/validators/GnoValidatorsChecker.sol";
import {GnoRewardSplitter} from "../contracts/misc/GnoRewardSplitter.sol";
import {GnoDaiDistributor} from "../contracts/misc/GnoDaiDistributor.sol";
import {RewardSplitterFactory} from "../contracts/misc/RewardSplitterFactory.sol";
import {GnoGenesisVault} from "../contracts/vaults/gnosis/GnoGenesisVault.sol";
import {GnoVault} from "../contracts/vaults/gnosis/GnoVault.sol";
import {GnoErc20Vault} from "../contracts/vaults/gnosis/GnoErc20Vault.sol";
import {GnoBlocklistVault} from "../contracts/vaults/gnosis/GnoBlocklistVault.sol";
import {GnoBlocklistErc20Vault} from "../contracts/vaults/gnosis/GnoBlocklistErc20Vault.sol";
import {GnoPrivVault} from "../contracts/vaults/gnosis/GnoPrivVault.sol";
import {GnoPrivErc20Vault} from "../contracts/vaults/gnosis/GnoPrivErc20Vault.sol";
import {GnoVaultFactory} from "../contracts/vaults/gnosis/GnoVaultFactory.sol";
import {Network} from "./Network.sol";

contract UpgradeGnoNetwork is Network {
    address public consolidationsChecker;
    address public validatorsChecker;
    address public rewardSplitterFactory;
    address public gnoDaiDistributor;

    address[] public vaultImpls;
    Factory[] public vaultFactories;

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address sender = vm.addr(privateKey);
        console.log("Deploying from: ", sender);

        vm.startBroadcast(privateKey);
        Deployment memory deployment = getDeploymentData();

        // Deploy common contracts
        consolidationsChecker = address(new ConsolidationsChecker(deployment.keeper));
        validatorsChecker = address(
            new GnoValidatorsChecker(
                deployment.validatorsRegistry,
                deployment.keeper,
                deployment.vaultsRegistry,
                deployment.depositDataRegistry,
                deployment.gnoToken
            )
        );
        address rewardsSplitterImpl = address(new GnoRewardSplitter(deployment.gnoToken));
        rewardSplitterFactory = address(new RewardSplitterFactory(rewardsSplitterImpl));
        gnoDaiDistributor = address(
            new GnoDaiDistributor(
                deployment.sDaiToken,
                deployment.vaultsRegistry,
                deployment.savingsXDaiAdapter,
                deployment.merkleDistributor
            )
        );

        _deployImplementations();
        _deployFactories();
        vm.stopBroadcast();

        generateGovernorTxJson(vaultImpls, vaultFactories);
        generateUpgradesJson(vaultImpls);
        generateAddressesJson(
            vaultFactories, validatorsChecker, consolidationsChecker, rewardSplitterFactory, gnoDaiDistributor
        );
    }

    function _deployImplementations() internal {
        // constructors for implementations
        IGnoVault.GnoVaultConstructorArgs memory vaultArgs = _getGnoVaultConstructorArgs();
        IGnoErc20Vault.GnoErc20VaultConstructorArgs memory erc20VaultArgs = _getGnoErc20VaultConstructorArgs();
        Deployment memory deployment = getDeploymentData();

        // update exited assets claim delay for public vaults
        vaultArgs.exitingAssetsClaimDelay = PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY;
        erc20VaultArgs.exitingAssetsClaimDelay = PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY;

        // deploy genesis vault
        GnoGenesisVault gnoGenesisVault =
            new GnoGenesisVault(vaultArgs, deployment.legacyPoolEscrow, deployment.legacyRewardToken);

        // deploy public vaults
        GnoVault gnoVault = new GnoVault(vaultArgs);
        GnoErc20Vault gnoErc20Vault = new GnoErc20Vault(erc20VaultArgs);

        // deploy blocklist vaults
        GnoBlocklistVault gnoBlocklistVault = new GnoBlocklistVault(vaultArgs);
        GnoBlocklistErc20Vault gnoBlocklistErc20Vault = new GnoBlocklistErc20Vault(erc20VaultArgs);

        // update exited assets claim delay for private vaults
        vaultArgs.exitingAssetsClaimDelay = PRIVATE_VAULT_EXITED_ASSETS_CLAIM_DELAY;
        erc20VaultArgs.exitingAssetsClaimDelay = PRIVATE_VAULT_EXITED_ASSETS_CLAIM_DELAY;

        // deploy private vaults
        GnoPrivVault gnoPrivVault = new GnoPrivVault(vaultArgs);
        GnoPrivErc20Vault gnoPrivErc20Vault = new GnoPrivErc20Vault(erc20VaultArgs);

        vaultImpls.push(address(gnoGenesisVault));
        vaultImpls.push(address(gnoVault));
        vaultImpls.push(address(gnoErc20Vault));
        vaultImpls.push(address(gnoBlocklistVault));
        vaultImpls.push(address(gnoBlocklistErc20Vault));
        vaultImpls.push(address(gnoPrivVault));
        vaultImpls.push(address(gnoPrivErc20Vault));
    }

    function _deployFactories() internal {
        Deployment memory deployment = getDeploymentData();
        for (uint256 i = 0; i < vaultImpls.length; i++) {
            address vaultImpl = vaultImpls[i];
            bytes32 vaultId = IVaultVersion(vaultImpl).vaultId();

            // skip factory creation for GnoGenesisVault
            if (vaultId == keccak256("GnoGenesisVault")) {
                continue;
            }

            GnoVaultFactory factory =
                new GnoVaultFactory(vaultImpl, IVaultsRegistry(deployment.vaultsRegistry), deployment.gnoToken);
            if (vaultId == keccak256("GnoVault")) {
                vaultFactories.push(Factory({name: "VaultFactory", factory: address(factory)}));
            } else if (vaultId == keccak256("GnoErc20Vault")) {
                vaultFactories.push(Factory({name: "Erc20VaultFactory", factory: address(factory)}));
            } else if (vaultId == keccak256("GnoBlocklistVault")) {
                vaultFactories.push(Factory({name: "BlocklistVaultFactory", factory: address(factory)}));
            } else if (vaultId == keccak256("GnoPrivVault")) {
                vaultFactories.push(Factory({name: "PrivVaultFactory", factory: address(factory)}));
            } else if (vaultId == keccak256("GnoBlocklistErc20Vault")) {
                vaultFactories.push(Factory({name: "BlocklistErc20VaultFactory", factory: address(factory)}));
            } else if (vaultId == keccak256("GnoPrivErc20Vault")) {
                vaultFactories.push(Factory({name: "PrivErc20VaultFactory", factory: address(factory)}));
            }
        }
    }

    function _getGnoVaultConstructorArgs() internal returns (IGnoVault.GnoVaultConstructorArgs memory) {
        Deployment memory deployment = getDeploymentData();
        return IGnoVault.GnoVaultConstructorArgs({
            keeper: deployment.keeper,
            vaultsRegistry: deployment.vaultsRegistry,
            validatorsRegistry: deployment.validatorsRegistry,
            validatorsWithdrawals: VALIDATORS_WITHDRAWALS,
            validatorsConsolidations: VALIDATORS_CONSOLIDATIONS,
            consolidationsChecker: consolidationsChecker,
            osTokenVaultController: deployment.osTokenVaultController,
            osTokenConfig: deployment.osTokenConfig,
            osTokenVaultEscrow: deployment.osTokenVaultEscrow,
            sharedMevEscrow: deployment.sharedMevEscrow,
            depositDataRegistry: deployment.depositDataRegistry,
            gnoToken: deployment.gnoToken,
            gnoDaiDistributor: gnoDaiDistributor,
            exitingAssetsClaimDelay: PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY
        });
    }

    function _getGnoErc20VaultConstructorArgs() internal returns (IGnoErc20Vault.GnoErc20VaultConstructorArgs memory) {
        Deployment memory deployment = getDeploymentData();
        return IGnoErc20Vault.GnoErc20VaultConstructorArgs({
            keeper: deployment.keeper,
            vaultsRegistry: deployment.vaultsRegistry,
            validatorsRegistry: deployment.validatorsRegistry,
            validatorsWithdrawals: VALIDATORS_WITHDRAWALS,
            validatorsConsolidations: VALIDATORS_CONSOLIDATIONS,
            consolidationsChecker: consolidationsChecker,
            osTokenVaultController: deployment.osTokenVaultController,
            osTokenConfig: deployment.osTokenConfig,
            osTokenVaultEscrow: deployment.osTokenVaultEscrow,
            sharedMevEscrow: deployment.sharedMevEscrow,
            depositDataRegistry: deployment.depositDataRegistry,
            gnoToken: deployment.gnoToken,
            gnoDaiDistributor: gnoDaiDistributor,
            exitingAssetsClaimDelay: PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY
        });
    }
}
