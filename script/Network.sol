// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IVaultVersion} from "../contracts/interfaces/IVaultVersion.sol";
import {IVaultsRegistry} from "../contracts/interfaces/IVaultsRegistry.sol";

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

    uint64 internal constant PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY = 1 days;
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
        address sharedMevEscrow;
        address osToken;
        address osTokenConfig;
        address osTokenVaultController;
        address osTokenVaultEscrow;
        address osTokenFlashLoans;
        address priceFeed;
        address validatorsRegistry;
        address legacyPoolEscrow;
        address legacyRewardToken;
        address merkleDistributor;
        address gnoToken;
        address sDaiToken;
    }

    struct Factory {
        string name;
        address factory;
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

    function getUpgradesFilePath() internal view returns (string memory) {
        string memory networkName = getNetworkName();
        return string.concat("./deployments/", networkName, "-vault-upgrades.json");
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
        deployment.sharedMevEscrow = deploymentData.readAddress(".SharedMevEscrow");
        deployment.osToken = deploymentData.readAddress(".OsToken");
        deployment.osTokenConfig = deploymentData.readAddress(".OsTokenConfig");
        deployment.osTokenVaultController = deploymentData.readAddress(".OsTokenVaultController");
        deployment.osTokenVaultEscrow = deploymentData.readAddress(".OsTokenVaultEscrow");
        deployment.osTokenFlashLoans = deploymentData.readAddress(".OsTokenFlashLoans");
        deployment.priceFeed = deploymentData.readAddress(".PriceFeed");
        deployment.validatorsRegistry = deploymentData.readAddress(".ValidatorsRegistry");
        deployment.legacyPoolEscrow = deploymentData.readAddress(".LegacyPoolEscrow");
        deployment.legacyRewardToken = deploymentData.readAddress(".LegacyRewardToken");
        deployment.merkleDistributor = deploymentData.readAddress(".MerkleDistributor");

        bool isGnosis = isGnosisNetwork();
        if (isGnosis) {
            deployment.gnoToken = deploymentData.readAddress(".GnoToken");
            deployment.sDaiToken = deploymentData.readAddress(".SDaiToken");
            deployment.foxVault = address(0);
        } else {
            deployment.gnoToken = address(0);
            deployment.sDaiToken = address(0);
            deployment.foxVault = deploymentData.readAddress(".FoxVault");
        }
        _deployment = deployment;
        return deployment;
    }

    function generateGovernorTxJson(address[] memory vaultImpls, Factory[] memory vaultFactories) internal {
        if (_governorCalls.length > 0) {
            return;
        }

        bool removePrevVaultFactories = vm.envBool("REMOVE_PREV_FACTORIES");

        for (uint256 i = 0; i < vaultImpls.length; i++) {
            _governorCalls.push(_serializeAddVaultImpl(vaultImpls[i]));
        }

        for (uint256 i = 0; i < vaultFactories.length; i++) {
            _governorCalls.push(_serializeAddFactory(vaultFactories[i].factory));
        }

        if (removePrevVaultFactories) {
            Deployment memory deployment = getDeploymentData();
            _governorCalls.push(_serializeRemoveFactory(deployment.vaultFactory));
            _governorCalls.push(_serializeRemoveFactory(deployment.privVaultFactory));
            _governorCalls.push(_serializeRemoveFactory(deployment.blocklistVaultFactory));
            _governorCalls.push(_serializeRemoveFactory(deployment.erc20VaultFactory));
            _governorCalls.push(_serializeRemoveFactory(deployment.privErc20VaultFactory));
            _governorCalls.push(_serializeRemoveFactory(deployment.blocklistErc20VaultFactory));
        }

        string memory output = vm.serializeString("governorCalls", "transactions", _governorCalls);
        string memory filePath = getGovernorTxsFilePath();
        vm.writeJson(output, filePath);
    }

    function generateUpgradesJson(address[] memory vaultImpls) internal {
        string memory upgrades = "upgrades";

        string memory output;
        for (uint256 i = 0; i < vaultImpls.length; i++) {
            address vaultImpl = vaultImpls[i];
            bytes32 vaultId = IVaultVersion(vaultImpl).vaultId();
            uint8 version = IVaultVersion(vaultImpl).version();

            string memory object = vm.serializeAddress(Strings.toString(i), Strings.toString(version), vaultImpl);
            output = vm.serializeString(upgrades, Strings.toHexString(uint256(vaultId)), object);
        }
        vm.writeJson(output, getUpgradesFilePath());
    }

    function generateAddressesJson(
        Factory[] memory newFactories,
        address validatorsChecker,
        address consolidationsChecker,
        address rewardSplitterFactory,
        address curatorsRegistry,
        address balancedCurator
    ) internal {
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
        vm.serializeAddress(json, "ValidatorsRegistry", deployment.validatorsRegistry);
        vm.serializeAddress(json, "LegacyPoolEscrow", deployment.legacyPoolEscrow);
        vm.serializeAddress(json, "LegacyRewardToken", deployment.legacyRewardToken);
        vm.serializeAddress(json, "MerkleDistributor", deployment.merkleDistributor);
        vm.serializeAddress(json, "CuratorsRegistry", curatorsRegistry);
        vm.serializeAddress(json, "BalancedCurator", balancedCurator);

        for (uint256 i = 0; i < newFactories.length; i++) {
            Factory memory factory = newFactories[i];
            vm.serializeAddress(json, factory.name, factory.factory);
        }

        bool isGnosis = isGnosisNetwork();
        if (isGnosis) {
            vm.serializeAddress(json, "GnoToken", deployment.gnoToken);
            vm.serializeAddress(json, "SDaiToken", deployment.sDaiToken);
        } else {
            vm.serializeAddress(json, "FoxVault", deployment.foxVault);
        }

        vm.serializeAddress(json, "ValidatorsChecker", validatorsChecker);
        vm.serializeAddress(json, "ConsolidationsChecker", consolidationsChecker);
        string memory output = vm.serializeAddress(json, "RewardSplitterFactory", rewardSplitterFactory);

        string memory path = string.concat("./deployments/", getNetworkName(), "-new.json");
        vm.writeJson(output, path);
    }

    function _serializeAddVaultImpl(address vaultImpl) private returns (string memory) {
        string memory object = "addVaultImpl";
        Deployment memory deployment = getDeploymentData();
        vm.serializeAddress(object, "to", deployment.vaultsRegistry);
        vm.serializeString(object, "operation", "0");
        vm.serializeString(object, "method", "addVaultImpl(address)");
        vm.serializeString(object, "value", "0.0");
        vm.serializeBytes(
            object,
            "data",
            abi.encodeWithSelector(IVaultsRegistry(deployment.vaultsRegistry).addVaultImpl.selector, vaultImpl)
        );

        address[] memory params = new address[](1);
        params[0] = vaultImpl;
        return vm.serializeAddress(object, "params", params);
    }

    function _serializeAddFactory(address factory) private returns (string memory) {
        string memory object = "addFactory";
        Deployment memory deployment = getDeploymentData();
        vm.serializeAddress(object, "to", deployment.vaultsRegistry);
        vm.serializeString(object, "operation", "0");
        vm.serializeString(object, "method", "addFactory(address)");
        vm.serializeString(object, "value", "0.0");
        vm.serializeBytes(
            object,
            "data",
            abi.encodeWithSelector(IVaultsRegistry(deployment.vaultsRegistry).addFactory.selector, factory)
        );

        address[] memory params = new address[](1);
        params[0] = factory;
        return vm.serializeAddress(object, "params", params);
    }

    function _serializeRemoveFactory(address factory) private returns (string memory) {
        string memory object = "removeFactory";
        Deployment memory deployment = getDeploymentData();
        vm.serializeAddress(object, "to", deployment.vaultsRegistry);
        vm.serializeString(object, "operation", "0");
        vm.serializeString(object, "method", "removeFactory(address)");
        vm.serializeString(object, "value", "0.0");
        vm.serializeBytes(
            object,
            "data",
            abi.encodeWithSelector(IVaultsRegistry(deployment.vaultsRegistry).removeFactory.selector, factory)
        );

        address[] memory params = new address[](1);
        params[0] = factory;
        return vm.serializeAddress(object, "params", params);
    }
}
