// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IOsTokenConfig} from "../contracts/interfaces/IOsTokenConfig.sol";

/**
 * @title Network
 * @author StakeWise
 * @notice Contains utils for network constants
 */
abstract contract Network is Script {
    using stdJson for string;

    uint256 internal constant MAINNET = 1;
    uint256 internal constant HOODI = 560048;
    uint256 internal constant CHIADO = 10200;
    uint256 internal constant GNOSIS = 100;

    uint64 internal constant PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY = 15 hours;
    // disable delay for private vaults as stakers are KYC'd
    uint64 internal constant PRIVATE_VAULT_EXITED_ASSETS_CLAIM_DELAY = 0;
    address internal constant VALIDATORS_WITHDRAWALS = 0x00000961Ef480Eb55e80D19ad83579A64c007002;
    address internal constant VALIDATORS_CONSOLIDATIONS = 0x0000BBdDc7CE488642fb579F8B00f3a590007251;

    struct Deployment {
        address keeper;
        address vaultsRegistry;
        address depositDataRegistry;
        address genesisVault;
        address foxVault;
        address vaultFactory;
        address privVaultFactory;
        address blocklistVaultFactory;
        address erc20VaultFactory;
        address privErc20VaultFactory;
        address blocklistErc20VaultFactory;
        address metaVaultFactory;
        address privMetaVaultFactory;
        address erc20MetaVaultFactory;
        address privErc20MetaVaultFactory;
        address validatorsChecker;
        address osTokenRedeemer;
        address communityVault;
        address nodesManager;
        address sharedMevEscrow;
        address osToken;
        address osTokenConfig;
        address osTokenVaultController;
        address osTokenVaultEscrow;
        address osTokenFlashLoans;
        address priceFeed;
        address legacyPoolEscrow;
        address legacyRewardToken;
        address merkleDistributor;
        address curatorsRegistry;
        address balancedCurator;
        address consolidationsChecker;
        address rewardSplitterFactory;
        address subVaultsRegistryFactory;
    }

    Deployment private _deployment;
    string[] private _governorCalls;

    function getNetworkName() internal view returns (string memory) {
        uint256 chainId = block.chainid;
        if (chainId == MAINNET) {
            return "mainnet";
        } else if (chainId == HOODI) {
            return "hoodi";
        } else if (chainId == GNOSIS) {
            return "gnosis";
        } else if (chainId == CHIADO) {
            return "chiado";
        } else {
            revert("Unsupported chain ID");
        }
    }

    function isGnosisNetwork() internal view returns (bool) {
        return block.chainid == GNOSIS || block.chainid == CHIADO;
    }

    function getDeploymentFilePath() internal view returns (string memory) {
        string memory networkName = getNetworkName();
        return string.concat("./deployments/", networkName, ".json");
    }

    function getGovernorTxsFilePath() internal view returns (string memory) {
        string memory networkName = getNetworkName();
        return string.concat("./deployments/", networkName, "-governor-txs.json");
    }

    function getDeploymentData() internal returns (Deployment memory) {
        Deployment memory deployment = _deployment;
        if (deployment.keeper != address(0)) {
            return deployment;
        }
        string memory deploymentData = vm.readFile(getDeploymentFilePath());
        deployment.vaultsRegistry = deploymentData.readAddress(".VaultsRegistry");
        deployment.keeper = deploymentData.readAddress(".Keeper");
        deployment.depositDataRegistry = deploymentData.readAddress(".DepositDataRegistry");
        deployment.genesisVault = deploymentData.readAddress(".GenesisVault");
        deployment.vaultFactory = deploymentData.readAddress(".VaultFactory");
        deployment.privVaultFactory = deploymentData.readAddress(".PrivVaultFactory");
        deployment.blocklistVaultFactory = deploymentData.readAddress(".BlocklistVaultFactory");
        deployment.erc20VaultFactory = deploymentData.readAddress(".Erc20VaultFactory");
        deployment.privErc20VaultFactory = deploymentData.readAddress(".PrivErc20VaultFactory");
        deployment.blocklistErc20VaultFactory = deploymentData.readAddress(".BlocklistErc20VaultFactory");
        deployment.validatorsChecker = deploymentData.readAddress(".ValidatorsChecker");
        deployment.osTokenRedeemer = deploymentData.readAddress(".OsTokenRedeemer");
        if (!isGnosisNetwork()) {
            deployment.metaVaultFactory = deploymentData.readAddress(".MetaVaultFactory");
            deployment.privMetaVaultFactory = deploymentData.readAddress(".PrivMetaVaultFactory");
            deployment.erc20MetaVaultFactory = deploymentData.readAddress(".Erc20MetaVaultFactory");
            deployment.privErc20MetaVaultFactory = deploymentData.readAddress(".PrivErc20MetaVaultFactory");
            deployment.communityVault = deploymentData.readAddress(".CommunityVault");
            deployment.nodesManager = deploymentData.readAddress(".NodesManager");
        }
        deployment.sharedMevEscrow = deploymentData.readAddress(".SharedMevEscrow");
        deployment.osToken = deploymentData.readAddress(".OsToken");
        deployment.osTokenConfig = deploymentData.readAddress(".OsTokenConfig");
        deployment.osTokenVaultController = deploymentData.readAddress(".OsTokenVaultController");
        deployment.osTokenVaultEscrow = deploymentData.readAddress(".OsTokenVaultEscrow");
        deployment.osTokenFlashLoans = deploymentData.readAddress(".OsTokenFlashLoans");
        deployment.priceFeed = deploymentData.readAddress(".PriceFeed");
        deployment.legacyPoolEscrow = deploymentData.readAddress(".LegacyPoolEscrow");
        deployment.legacyRewardToken = deploymentData.readAddress(".LegacyRewardToken");
        deployment.merkleDistributor = deploymentData.readAddress(".MerkleDistributor");
        deployment.foxVault = isGnosisNetwork() ? address(0) : deploymentData.readAddress(".FoxVault");
        deployment.curatorsRegistry = deploymentData.readAddress(".CuratorsRegistry");
        deployment.balancedCurator = deploymentData.readAddress(".BalancedCurator");
        deployment.consolidationsChecker = deploymentData.readAddress(".ConsolidationsChecker");
        deployment.rewardSplitterFactory = deploymentData.readAddress(".RewardSplitterFactory");
        deployment.subVaultsRegistryFactory = deploymentData.readAddress(".SubVaultsRegistryFactory");

        _deployment = deployment;
        return deployment;
    }

    function generateGovernorTxJson(address osTokenRedeemer) internal {
        if (_governorCalls.length > 0) {
            return;
        }

        _governorCalls.push(_serializeSetRedeemer(osTokenRedeemer));

        string memory output = vm.serializeString("governorCalls", "transactions", _governorCalls);
        string memory filePath = getGovernorTxsFilePath();
        vm.writeJson(output, filePath);
    }

    function generateAddressesJson(address osTokenRedeemer) internal {
        Deployment memory deployment = getDeploymentData();

        string memory json = "addresses";
        vm.serializeAddress(json, "VaultsRegistry", deployment.vaultsRegistry);
        vm.serializeAddress(json, "Keeper", deployment.keeper);
        vm.serializeAddress(json, "DepositDataRegistry", deployment.depositDataRegistry);
        vm.serializeAddress(json, "GenesisVault", deployment.genesisVault);
        vm.serializeAddress(json, "SharedMevEscrow", deployment.sharedMevEscrow);
        vm.serializeAddress(json, "OsToken", deployment.osToken);
        vm.serializeAddress(json, "OsTokenConfig", deployment.osTokenConfig);
        vm.serializeAddress(json, "OsTokenVaultController", deployment.osTokenVaultController);
        vm.serializeAddress(json, "OsTokenVaultEscrow", deployment.osTokenVaultEscrow);
        vm.serializeAddress(json, "OsTokenFlashLoans", deployment.osTokenFlashLoans);
        vm.serializeAddress(json, "PriceFeed", deployment.priceFeed);
        vm.serializeAddress(json, "LegacyPoolEscrow", deployment.legacyPoolEscrow);
        vm.serializeAddress(json, "LegacyRewardToken", deployment.legacyRewardToken);
        vm.serializeAddress(json, "MerkleDistributor", deployment.merkleDistributor);
        vm.serializeAddress(json, "CuratorsRegistry", deployment.curatorsRegistry);
        vm.serializeAddress(json, "BalancedCurator", deployment.balancedCurator);
        vm.serializeAddress(json, "ConsolidationsChecker", deployment.consolidationsChecker);

        vm.serializeAddress(json, "RewardSplitterFactory", deployment.rewardSplitterFactory);
        vm.serializeAddress(json, "VaultFactory", deployment.vaultFactory);
        vm.serializeAddress(json, "PrivVaultFactory", deployment.privVaultFactory);
        vm.serializeAddress(json, "BlocklistVaultFactory", deployment.blocklistVaultFactory);
        vm.serializeAddress(json, "Erc20VaultFactory", deployment.erc20VaultFactory);
        vm.serializeAddress(json, "PrivErc20VaultFactory", deployment.privErc20VaultFactory);
        vm.serializeAddress(json, "BlocklistErc20VaultFactory", deployment.blocklistErc20VaultFactory);

        if (!isGnosisNetwork()) {
            vm.serializeAddress(json, "MetaVaultFactory", deployment.metaVaultFactory);
            vm.serializeAddress(json, "PrivMetaVaultFactory", deployment.privMetaVaultFactory);
            vm.serializeAddress(json, "Erc20MetaVaultFactory", deployment.erc20MetaVaultFactory);
            vm.serializeAddress(json, "PrivErc20MetaVaultFactory", deployment.privErc20MetaVaultFactory);
            vm.serializeAddress(json, "FoxVault", deployment.foxVault);
            vm.serializeAddress(json, "CommunityVault", deployment.communityVault);
            vm.serializeAddress(json, "NodesManager", deployment.nodesManager);
        }

        vm.serializeAddress(json, "OsTokenRedeemer", osTokenRedeemer);
        vm.serializeAddress(json, "SubVaultsRegistryFactory", deployment.subVaultsRegistryFactory);

        string memory output = vm.serializeAddress(json, "ValidatorsChecker", deployment.validatorsChecker);
        string memory path = string.concat("./deployments/", getNetworkName(), "-new.json");
        vm.writeJson(output, path);
    }

    function _serializeSetRedeemer(address osTokenRedeemer) private returns (string memory) {
        string memory object = "setRedeemer";
        Deployment memory deployment = getDeploymentData();
        vm.serializeAddress(object, "to", deployment.osTokenConfig);
        vm.serializeString(object, "operation", "0");
        vm.serializeString(object, "method", "setRedeemer(address)");
        vm.serializeString(object, "value", "0.0");
        vm.serializeBytes(object, "data", abi.encodeCall(IOsTokenConfig.setRedeemer, (osTokenRedeemer)));

        address[] memory params = new address[](1);
        params[0] = osTokenRedeemer;
        return vm.serializeAddress(object, "params", params);
    }
}
