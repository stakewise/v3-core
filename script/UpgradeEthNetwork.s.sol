// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {console} from "forge-std/console.sol";
import {IEthCommunityVault} from "../contracts/interfaces/IEthCommunityVault.sol";
import {IEthErc20Vault} from "../contracts/interfaces/IEthErc20Vault.sol";
import {IEthErc20MetaVault} from "../contracts/interfaces/IEthErc20MetaVault.sol";
import {IEthMetaVault} from "../contracts/interfaces/IEthMetaVault.sol";
import {IEthVault} from "../contracts/interfaces/IEthVault.sol";
import {IVaultVersion} from "../contracts/interfaces/IVaultVersion.sol";
import {IVaultsRegistry} from "../contracts/interfaces/IVaultsRegistry.sol";
import {EthNodesManager} from "../contracts/nodes/EthNodesManager.sol";
import {EthOsTokenRedeemer} from "../contracts/tokens/EthOsTokenRedeemer.sol";
import {EthValidatorsChecker} from "../contracts/validators/EthValidatorsChecker.sol";
import {SubVaultsRegistry} from "../contracts/vaults/SubVaultsRegistry.sol";
import {SubVaultsRegistryFactory} from "../contracts/vaults/SubVaultsRegistryFactory.sol";
import {EthErc20MetaVault} from "../contracts/vaults/ethereum/EthErc20MetaVault.sol";
import {EthMetaVault} from "../contracts/vaults/ethereum/EthMetaVault.sol";
import {EthMetaVaultFactory} from "../contracts/vaults/ethereum/EthMetaVaultFactory.sol";
import {EthPrivErc20MetaVault} from "../contracts/vaults/ethereum/EthPrivErc20MetaVault.sol";
import {EthPrivMetaVault} from "../contracts/vaults/ethereum/EthPrivMetaVault.sol";
import {EthCommunityVault} from "../contracts/vaults/ethereum/custom/EthCommunityVault.sol";
import {Network} from "./Network.sol";

contract UpgradeEthNetwork is Network {
    uint256 private constant _securityDeposit = 1e9;

    address public osTokenRedeemerOwner;
    address public validatorsRegistry;
    uint256 public osTokenRedeemerExitQueueUpdateDelay;

    address public validatorsChecker;
    address public osTokenRedeemer;
    address public subVaultsRegistryFactory;
    address public communityVault;
    address public nodesManager;

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

        // Deploy SubVaultsRegistryFactory
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
        _deployCommunityVault();
        vm.stopBroadcast();

        generateGovernorTxJson(vaultImpls, vaultFactories, osTokenRedeemer, communityVault);
        generateUpgradesJson(vaultImpls);
        generateAddressesJson(
            vaultFactories, validatorsChecker, osTokenRedeemer, subVaultsRegistryFactory, communityVault, nodesManager
        );
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

    function _deployCommunityVault() internal {
        Deployment memory deployment = getDeploymentData();

        // Read community vault init params
        address vaultAdmin = vm.envAddress("COMMUNITY_VAULT_ADMIN");
        uint16 vaultFeePercent = SafeCast.toUint16(vm.envUint("COMMUNITY_VAULT_FEE_PERCENT"));
        string memory vaultName = vm.envString("COMMUNITY_VAULT_NAME");
        string memory vaultSymbol = vm.envString("COMMUNITY_VAULT_SYMBOL");

        // Read nodes manager init params
        address nodesManagerOwner = vm.envAddress("NODES_MANAGER_OWNER");
        uint256 minDepositAssets = vm.envUint("NODES_MANAGER_MIN_DEPOSIT_ASSETS");
        uint16 minBalancePercent = SafeCast.toUint16(vm.envUint("NODES_MANAGER_MIN_BALANCE_PERCENT"));
        uint256 stateUpdateDelay = vm.envUint("NODES_MANAGER_STATE_UPDATE_DELAY");

        // Deploy EthCommunityVault implementation
        IEthErc20Vault.EthErc20VaultConstructorArgs memory vaultArgs = IEthErc20Vault.EthErc20VaultConstructorArgs({
            keeper: deployment.keeper,
            vaultsRegistry: deployment.vaultsRegistry,
            validatorsRegistry: validatorsRegistry,
            validatorsWithdrawals: VALIDATORS_WITHDRAWALS,
            validatorsConsolidations: VALIDATORS_CONSOLIDATIONS,
            consolidationsChecker: deployment.consolidationsChecker,
            osTokenVaultController: deployment.osTokenVaultController,
            osTokenConfig: deployment.osTokenConfig,
            osTokenVaultEscrow: deployment.osTokenVaultEscrow,
            sharedMevEscrow: deployment.sharedMevEscrow,
            depositDataRegistry: deployment.depositDataRegistry,
            exitingAssetsClaimDelay: PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY
        });
        address communityVaultImpl = address(new EthCommunityVault(vaultArgs));

        // Deploy vault proxy (uninitialized)
        communityVault = address(new ERC1967Proxy(communityVaultImpl, ""));

        // Deploy EthNodesManager implementation + proxy
        EthNodesManager nodesManagerImpl = new EthNodesManager(communityVault, deployment.keeper);
        nodesManager = address(
            new ERC1967Proxy(
                address(nodesManagerImpl),
                abi.encodeWithSelector(
                    EthNodesManager.initialize.selector,
                    nodesManagerOwner,
                    minDepositAssets,
                    minBalancePercent,
                    stateUpdateDelay
                )
            )
        );

        // Initialize vault with NodesManager
        bytes memory initParams = abi.encode(
            IEthCommunityVault.EthCommunityVaultInitParams({
                admin: vaultAdmin,
                nodesManager: nodesManager,
                capacity: type(uint256).max,
                feePercent: vaultFeePercent,
                name: vaultName,
                symbol: vaultSymbol,
                metadataIpfsHash: ""
            })
        );
        IEthErc20Vault(communityVault).initialize{value: _securityDeposit}(initParams);
    }
}
