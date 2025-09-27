// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {console} from "forge-std/console.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
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
import {EthMetaVault, IEthMetaVault} from "../contracts/vaults/ethereum/custom/EthMetaVault.sol";
import {EthVaultFactory} from "../contracts/vaults/ethereum/EthVaultFactory.sol";
import {EthMetaVaultFactory} from "../contracts/vaults/ethereum/custom/EthMetaVaultFactory.sol";
import {EthValidatorsChecker} from "../contracts/validators/EthValidatorsChecker.sol";
import {CuratorsRegistry, ICuratorsRegistry} from "../contracts/curators/CuratorsRegistry.sol";
import {BalancedCurator} from "../contracts/curators/BalancedCurator.sol";
import {EthRewardSplitter} from "../contracts/misc/EthRewardSplitter.sol";
import {RewardSplitterFactory} from "../contracts/misc/RewardSplitterFactory.sol";
import {EthOsTokenRedeemer} from "../contracts/tokens/EthOsTokenRedeemer.sol";
import {Network} from "./Network.sol";

contract UpgradeEthNetwork is Network {
    address public metaVaultFactoryOwner;
    address public osTokenRedeemerOwner;
    address public validatorsRegistry;
    uint256 public osTokenRedeemerExitQueueUpdateDelay;

    address public consolidationsChecker;
    address public validatorsChecker;
    address public rewardSplitterFactory;
    address public curatorsRegistry;
    address public balancedCurator;
    address public osTokenRedeemer;

    address[] public vaultImpls;
    Factory[] public vaultFactories;

    function run() external {
        metaVaultFactoryOwner = vm.envAddress("META_VAULT_FACTORY_OWNER");
        osTokenRedeemerOwner = vm.envAddress("OS_TOKEN_REDEEMER_OWNER");
        osTokenRedeemerExitQueueUpdateDelay = vm.envUint("OS_TOKEN_REDEEMER_EXIT_QUEUE_UPDATE_DELAY");
        validatorsRegistry = vm.envAddress("VALIDATORS_REGISTRY");
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address sender = vm.addr(privateKey);
        console.log("Deploying from: ", sender);

        Deployment memory deployment = getDeploymentData();

        vm.startBroadcast(privateKey);

        // Deploy common contracts
        consolidationsChecker = address(new ConsolidationsChecker(deployment.keeper));
        validatorsChecker = address(
            new EthValidatorsChecker(
                validatorsRegistry,
                deployment.keeper,
                deployment.vaultsRegistry,
                deployment.depositDataRegistry,
                deployment.legacyPoolEscrow
            )
        );
        address rewardsSplitterImpl = address(new EthRewardSplitter());
        rewardSplitterFactory = address(new RewardSplitterFactory(rewardsSplitterImpl));

        // deploy curators
        curatorsRegistry = address(new CuratorsRegistry());
        balancedCurator = address(new BalancedCurator());
        ICuratorsRegistry(curatorsRegistry).addCurator(balancedCurator);
        ICuratorsRegistry(curatorsRegistry).initialize(Ownable(deployment.vaultsRegistry).owner());

        // deploy OsToken redeemer
        osTokenRedeemer = address(
            new EthOsTokenRedeemer(
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
        generateAddressesJson(
            vaultFactories,
            validatorsChecker,
            consolidationsChecker,
            rewardSplitterFactory,
            curatorsRegistry,
            balancedCurator,
            osTokenRedeemer
        );
    }

    function _deployImplementations() internal {
        // constructors for implementations
        IEthVault.EthVaultConstructorArgs memory vaultArgs = _getEthVaultConstructorArgs();
        IEthErc20Vault.EthErc20VaultConstructorArgs memory erc20VaultArgs = _getEthErc20VaultConstructorArgs();
        IEthMetaVault.EthMetaVaultConstructorArgs memory metaVaultArgs = _getEthMetaVaultConstructorArgs();
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

        // deploy MetaVault
        EthMetaVault ethMetaVault = new EthMetaVault(metaVaultArgs);

        vaultImpls.push(address(ethGenesisVault));
        vaultImpls.push(address(ethVault));
        vaultImpls.push(address(ethErc20Vault));
        vaultImpls.push(address(ethBlocklistVault));
        vaultImpls.push(address(ethBlocklistErc20Vault));
        vaultImpls.push(address(ethPrivVault));
        vaultImpls.push(address(ethPrivErc20Vault));
        vaultImpls.push(address(ethMetaVault));
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

            address factory;
            if (vaultId == keccak256("EthMetaVault")) {
                factory = address(
                    new EthMetaVaultFactory(
                        metaVaultFactoryOwner, vaultImpl, IVaultsRegistry(deployment.vaultsRegistry)
                    )
                );
                vaultFactories.push(Factory({name: "MetaVaultFactory", factory: factory}));
                continue;
            }

            factory = address(new EthVaultFactory(vaultImpl, IVaultsRegistry(deployment.vaultsRegistry)));
            if (vaultId == keccak256("EthVault")) {
                vaultFactories.push(Factory({name: "VaultFactory", factory: factory}));
            } else if (vaultId == keccak256("EthErc20Vault")) {
                vaultFactories.push(Factory({name: "Erc20VaultFactory", factory: factory}));
            } else if (vaultId == keccak256("EthBlocklistVault")) {
                vaultFactories.push(Factory({name: "BlocklistVaultFactory", factory: factory}));
            } else if (vaultId == keccak256("EthPrivVault")) {
                vaultFactories.push(Factory({name: "PrivVaultFactory", factory: factory}));
            } else if (vaultId == keccak256("EthBlocklistErc20Vault")) {
                vaultFactories.push(Factory({name: "BlocklistErc20VaultFactory", factory: factory}));
            } else if (vaultId == keccak256("EthPrivErc20Vault")) {
                vaultFactories.push(Factory({name: "PrivErc20VaultFactory", factory: factory}));
            }
        }
    }

    function _getEthVaultConstructorArgs() internal returns (IEthVault.EthVaultConstructorArgs memory) {
        Deployment memory deployment = getDeploymentData();
        return IEthVault.EthVaultConstructorArgs({
            keeper: deployment.keeper,
            vaultsRegistry: deployment.vaultsRegistry,
            validatorsRegistry: validatorsRegistry,
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
            validatorsRegistry: validatorsRegistry,
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

    function _getEthMetaVaultConstructorArgs() internal returns (IEthMetaVault.EthMetaVaultConstructorArgs memory) {
        Deployment memory deployment = getDeploymentData();
        return IEthMetaVault.EthMetaVaultConstructorArgs({
            keeper: deployment.keeper,
            vaultsRegistry: deployment.vaultsRegistry,
            osTokenVaultController: deployment.osTokenVaultController,
            osTokenConfig: deployment.osTokenConfig,
            osTokenVaultEscrow: deployment.osTokenVaultEscrow,
            curatorsRegistry: curatorsRegistry,
            exitingAssetsClaimDelay: PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY
        });
    }
}
