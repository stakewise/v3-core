// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {console} from "forge-std/console.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IGnoVault} from "../contracts/interfaces/IGnoVault.sol";
import {IGnoErc20Vault} from "../contracts/interfaces/IGnoErc20Vault.sol";
import {IVaultsRegistry} from "../contracts/interfaces/IVaultsRegistry.sol";
import {IVaultVersion} from "../contracts/interfaces/IVaultVersion.sol";
import {ConsolidationsChecker} from "../contracts/validators/ConsolidationsChecker.sol";
import {GnoValidatorsChecker} from "../contracts/validators/GnoValidatorsChecker.sol";
import {GnoRewardSplitter} from "../contracts/misc/GnoRewardSplitter.sol";
import {RewardSplitterFactory} from "../contracts/misc/RewardSplitterFactory.sol";
import {GnoGenesisVault} from "../contracts/vaults/gnosis/GnoGenesisVault.sol";
import {GnoVault} from "../contracts/vaults/gnosis/GnoVault.sol";
import {GnoErc20Vault} from "../contracts/vaults/gnosis/GnoErc20Vault.sol";
import {GnoBlocklistVault} from "../contracts/vaults/gnosis/GnoBlocklistVault.sol";
import {GnoBlocklistErc20Vault} from "../contracts/vaults/gnosis/GnoBlocklistErc20Vault.sol";
import {GnoPrivVault} from "../contracts/vaults/gnosis/GnoPrivVault.sol";
import {GnoPrivErc20Vault} from "../contracts/vaults/gnosis/GnoPrivErc20Vault.sol";
import {IGnoMetaVault, GnoMetaVault} from "../contracts/vaults/gnosis/custom/GnoMetaVault.sol";
import {GnoVaultFactory} from "../contracts/vaults/gnosis/GnoVaultFactory.sol";
import {GnoMetaVaultFactory} from "../contracts/vaults/gnosis/custom/GnoMetaVaultFactory.sol";
import {CuratorsRegistry, ICuratorsRegistry} from "../contracts/curators/CuratorsRegistry.sol";
import {BalancedCurator} from "../contracts/curators/BalancedCurator.sol";
import {OsTokenRedeemer} from "../contracts/tokens/OsTokenRedeemer.sol";
import {Network} from "./Network.sol";

contract UpgradeGnoNetwork is Network {
    address public metaVaultFactoryOwner;
    address public osTokenRedeemerOwner;
    address public validatorsRegistry;
    address public gnoToken;
    uint256 public osTokenRedeemerRootUpdateDelay;

    address public consolidationsChecker;
    address public validatorsChecker;
    address public rewardSplitterFactory;
    address public tokensConverterFactory;
    address public curatorsRegistry;
    address public balancedCurator;
    address public osTokenRedeemer;

    address[] public vaultImpls;
    Factory[] public vaultFactories;

    function run() external {
        metaVaultFactoryOwner = vm.envAddress("META_VAULT_FACTORY_OWNER");
        osTokenRedeemerOwner = vm.envAddress("OS_TOKEN_REDEEMER_OWNER");
        osTokenRedeemerRootUpdateDelay = vm.envUint("OS_TOKEN_REDEEMER_ROOT_UPDATE_DELAY");
        tokensConverterFactory = vm.envAddress("TOKENS_CONVERTER_FACTORY");
        validatorsRegistry = vm.envAddress("VALIDATORS_REGISTRY");
        gnoToken = vm.envAddress("GNO_TOKEN");
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address sender = vm.addr(privateKey);
        console.log("Deploying from: ", sender);

        Deployment memory deployment = getDeploymentData();

        vm.startBroadcast(privateKey);

        // Deploy common contracts
        consolidationsChecker = address(new ConsolidationsChecker(deployment.keeper));
        validatorsChecker = address(
            new GnoValidatorsChecker(
                validatorsRegistry,
                deployment.keeper,
                deployment.vaultsRegistry,
                deployment.depositDataRegistry,
                gnoToken
            )
        );
        address rewardsSplitterImpl = address(new GnoRewardSplitter(gnoToken));
        rewardSplitterFactory = address(new RewardSplitterFactory(rewardsSplitterImpl));

        // deploy curators
        curatorsRegistry = address(new CuratorsRegistry());
        balancedCurator = address(new BalancedCurator());
        ICuratorsRegistry(curatorsRegistry).addCurator(balancedCurator);
        ICuratorsRegistry(curatorsRegistry).initialize(Ownable(deployment.vaultsRegistry).owner());

        // deploy OsToken redeemer
        osTokenRedeemer = address(
            new OsTokenRedeemer(
                deployment.vaultsRegistry, deployment.osToken, osTokenRedeemerOwner, osTokenRedeemerRootUpdateDelay
            )
        );

        _deployImplementations();
        _deployFactories();
        vm.stopBroadcast();

        generateGovernorTxJson(vaultImpls, vaultFactories, curatorsRegistry, balancedCurator, osTokenRedeemer);
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
        IGnoVault.GnoVaultConstructorArgs memory vaultArgs = _getGnoVaultConstructorArgs();
        IGnoErc20Vault.GnoErc20VaultConstructorArgs memory erc20VaultArgs = _getGnoErc20VaultConstructorArgs();
        IGnoMetaVault.GnoMetaVaultConstructorArgs memory metaVaultArgs = _getGnoMetaVaultConstructorArgs();
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

        // deploy MetaVault
        GnoMetaVault gnoMetaVault = new GnoMetaVault(metaVaultArgs);

        vaultImpls.push(address(gnoGenesisVault));
        vaultImpls.push(address(gnoVault));
        vaultImpls.push(address(gnoErc20Vault));
        vaultImpls.push(address(gnoBlocklistVault));
        vaultImpls.push(address(gnoBlocklistErc20Vault));
        vaultImpls.push(address(gnoPrivVault));
        vaultImpls.push(address(gnoPrivErc20Vault));
        vaultImpls.push(address(gnoMetaVault));
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

            address factory;
            if (vaultId == keccak256("GnoMetaVault")) {
                factory = address(
                    new GnoMetaVaultFactory(
                        metaVaultFactoryOwner, vaultImpl, IVaultsRegistry(deployment.vaultsRegistry), gnoToken
                    )
                );
                vaultFactories.push(Factory({name: "MetaVaultFactory", factory: factory}));
                continue;
            }

            factory = address(new GnoVaultFactory(vaultImpl, IVaultsRegistry(deployment.vaultsRegistry), gnoToken));
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
            validatorsRegistry: validatorsRegistry,
            validatorsWithdrawals: VALIDATORS_WITHDRAWALS,
            validatorsConsolidations: VALIDATORS_CONSOLIDATIONS,
            consolidationsChecker: consolidationsChecker,
            osTokenVaultController: deployment.osTokenVaultController,
            osTokenConfig: deployment.osTokenConfig,
            osTokenVaultEscrow: deployment.osTokenVaultEscrow,
            sharedMevEscrow: deployment.sharedMevEscrow,
            depositDataRegistry: deployment.depositDataRegistry,
            gnoToken: gnoToken,
            tokensConverterFactory: tokensConverterFactory,
            exitingAssetsClaimDelay: PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY
        });
    }

    function _getGnoErc20VaultConstructorArgs() internal returns (IGnoErc20Vault.GnoErc20VaultConstructorArgs memory) {
        Deployment memory deployment = getDeploymentData();
        return IGnoErc20Vault.GnoErc20VaultConstructorArgs({
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
            gnoToken: gnoToken,
            tokensConverterFactory: tokensConverterFactory,
            exitingAssetsClaimDelay: PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY
        });
    }

    function _getGnoMetaVaultConstructorArgs() internal returns (IGnoMetaVault.GnoMetaVaultConstructorArgs memory) {
        Deployment memory deployment = getDeploymentData();
        return IGnoMetaVault.GnoMetaVaultConstructorArgs({
            keeper: deployment.keeper,
            vaultsRegistry: deployment.vaultsRegistry,
            osTokenVaultController: deployment.osTokenVaultController,
            osTokenConfig: deployment.osTokenConfig,
            osTokenVaultEscrow: deployment.osTokenVaultEscrow,
            curatorsRegistry: curatorsRegistry,
            gnoToken: gnoToken,
            exitingAssetsClaimDelay: PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY
        });
    }
}
