// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {console} from "forge-std/console.sol";
import {IEthVault} from "../contracts/interfaces/IEthVault.sol";
import {IEthErc20Vault} from "../contracts/interfaces/IEthErc20Vault.sol";
import {IVaultsRegistry} from "../contracts/interfaces/IVaultsRegistry.sol";
import {IVaultVersion} from "../contracts/interfaces/IVaultVersion.sol";
import {ConsolidationsChecker} from "../contracts/validators/ConsolidationsChecker.sol";
import {EthBlocklistErc20Vault} from "../contracts/vaults/ethereum/EthBlocklistErc20Vault.sol";
import {EthBlocklistVault} from "../contracts/vaults/ethereum/EthBlocklistVault.sol";
import {EthErc20Vault} from "../contracts/vaults/ethereum/EthErc20Vault.sol";
import {EthGenesisVault} from "../contracts/vaults/ethereum/EthGenesisVault.sol";
import {EthPrivErc20Vault} from "../contracts/vaults/ethereum/EthPrivErc20Vault.sol";
import {EthPrivVault} from "../contracts/vaults/ethereum/EthPrivVault.sol";
import {EthVault} from "../contracts/vaults/ethereum/EthVault.sol";
import {EthVaultFactory} from "../contracts/vaults/ethereum/EthVaultFactory.sol";
import {EthValidatorsChecker} from "../contracts/validators/EthValidatorsChecker.sol";
import {EthRewardSplitter} from "../contracts/misc/EthRewardSplitter.sol";
import {RewardSplitterFactory} from "../contracts/misc/RewardSplitterFactory.sol";
import {Network} from "./Network.sol";

contract UpgradeEthNetwork is Network {
    address public consolidationsChecker;
    address public validatorsChecker;
    address public rewardSplitterFactory;

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
            new EthValidatorsChecker(
                deployment.validatorsRegistry,
                deployment.keeper,
                deployment.vaultsRegistry,
                deployment.depositDataRegistry
            )
        );
        address rewardsSplitterImpl = address(new EthRewardSplitter());
        rewardSplitterFactory = address(new RewardSplitterFactory(rewardsSplitterImpl));

        _deployImplementations();
        _deployFactories();
        vm.stopBroadcast();

        generateGovernorTxJson(vaultImpls, vaultFactories);
        generateUpgradesJson(vaultImpls);
        generateAddressesJson(vaultFactories, validatorsChecker, consolidationsChecker, rewardSplitterFactory);
    }

    function _deployImplementations() internal {
        // constructors for implementations
        IEthVault.EthVaultConstructorArgs memory vaultArgs = _getEthVaultConstructorArgs();
        IEthErc20Vault.EthErc20VaultConstructorArgs memory erc20VaultArgs = _getEthErc20VaultConstructorArgs();
        Deployment memory deployment = getDeploymentData();

        // update exited assets claim delay for public vaults
        vaultArgs.exitingAssetsClaimDelay = PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY;
        erc20VaultArgs.exitingAssetsClaimDelay = PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY;

        // deploy genesis vault
        EthGenesisVault ethGenesisVault =
            new EthGenesisVault(vaultArgs, deployment.legacyPoolEscrow, deployment.legacyRewardToken);

        // deploy public vaults
        EthVault ethVault = new EthVault(vaultArgs);
        EthErc20Vault ethErc20Vault = new EthErc20Vault(erc20VaultArgs);

        // deploy blocklist vaults
        EthBlocklistVault ethBlocklistVault = new EthBlocklistVault(vaultArgs);
        EthBlocklistErc20Vault ethBlocklistErc20Vault = new EthBlocklistErc20Vault(erc20VaultArgs);

        // update exited assets claim delay for private vaults
        vaultArgs.exitingAssetsClaimDelay = PRIVATE_VAULT_EXITED_ASSETS_CLAIM_DELAY;
        erc20VaultArgs.exitingAssetsClaimDelay = PRIVATE_VAULT_EXITED_ASSETS_CLAIM_DELAY;

        // deploy private vaults
        EthPrivVault ethPrivVault = new EthPrivVault(vaultArgs);
        EthPrivErc20Vault ethPrivErc20Vault = new EthPrivErc20Vault(erc20VaultArgs);

        vaultImpls.push(address(ethGenesisVault));
        vaultImpls.push(address(ethVault));
        vaultImpls.push(address(ethErc20Vault));
        vaultImpls.push(address(ethBlocklistVault));
        vaultImpls.push(address(ethBlocklistErc20Vault));
        vaultImpls.push(address(ethPrivVault));
        vaultImpls.push(address(ethPrivErc20Vault));
    }

    function _deployFactories() internal {
        Deployment memory deployment = getDeploymentData();
        for (uint256 i = 0; i < vaultImpls.length; i++) {
            address vaultImpl = vaultImpls[i];
            bytes32 vaultId = IVaultVersion(vaultImpl).vaultId();

            // skip factory creation for EthGenesisVault or EthFoxVault
            if (vaultId == keccak256("EthGenesisVault") || vaultId == keccak256("EthFoxVault")) {
                continue;
            }

            EthVaultFactory factory = new EthVaultFactory(vaultImpl, IVaultsRegistry(deployment.vaultsRegistry));
            if (vaultId == keccak256("EthVault")) {
                vaultFactories.push(Factory({name: "VaultFactory", factory: address(factory)}));
            } else if (vaultId == keccak256("EthErc20Vault")) {
                vaultFactories.push(Factory({name: "Erc20VaultFactory", factory: address(factory)}));
            } else if (vaultId == keccak256("EthBlocklistVault")) {
                vaultFactories.push(Factory({name: "BlocklistVaultFactory", factory: address(factory)}));
            } else if (vaultId == keccak256("EthPrivVault")) {
                vaultFactories.push(Factory({name: "PrivVaultFactory", factory: address(factory)}));
            } else if (vaultId == keccak256("EthBlocklistErc20Vault")) {
                vaultFactories.push(Factory({name: "BlocklistErc20VaultFactory", factory: address(factory)}));
            } else if (vaultId == keccak256("EthPrivErc20Vault")) {
                vaultFactories.push(Factory({name: "PrivErc20VaultFactory", factory: address(factory)}));
            }
        }
    }

    function _getEthVaultConstructorArgs() internal returns (IEthVault.EthVaultConstructorArgs memory) {
        Deployment memory deployment = getDeploymentData();
        return IEthVault.EthVaultConstructorArgs({
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
            exitingAssetsClaimDelay: PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY
        });
    }

    function _getEthErc20VaultConstructorArgs() internal returns (IEthErc20Vault.EthErc20VaultConstructorArgs memory) {
        Deployment memory deployment = getDeploymentData();
        return IEthErc20Vault.EthErc20VaultConstructorArgs({
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
            exitingAssetsClaimDelay: PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY
        });
    }
}
