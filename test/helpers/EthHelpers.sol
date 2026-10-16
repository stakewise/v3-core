// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Test, stdStorage, StdStorage} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IKeeperValidators} from "../../contracts/interfaces/IKeeperValidators.sol";
import {IOsTokenConfig} from "../../contracts/interfaces/IOsTokenConfig.sol";
import {IOsTokenVaultController} from "../../contracts/interfaces/IOsTokenVaultController.sol";
import {IOsTokenVaultEscrow} from "../../contracts/interfaces/IOsTokenVaultEscrow.sol";
import {ISharedMevEscrow} from "../../contracts/interfaces/ISharedMevEscrow.sol";
import {IEthValidatorsRegistry} from "../../contracts/interfaces/IEthValidatorsRegistry.sol";
import {IKeeperRewards} from "../../contracts/interfaces/IKeeperRewards.sol";
import {IVaultState} from "../../contracts/interfaces/IVaultState.sol";
import {IEthMetaVault} from "../../contracts/interfaces/IEthMetaVault.sol";
import {IConsolidationsChecker} from "../../contracts/interfaces/IConsolidationsChecker.sol";
import {ConsolidationsChecker} from "../../contracts/validators/ConsolidationsChecker.sol";
import {EthBlocklistErc20Vault} from "../../contracts/vaults/ethereum/EthBlocklistErc20Vault.sol";
import {EthBlocklistVault} from "../../contracts/vaults/ethereum/EthBlocklistVault.sol";
import {EthErc20Vault, IEthErc20Vault} from "../../contracts/vaults/ethereum/EthErc20Vault.sol";
import {EthGenesisVault} from "../../contracts/vaults/ethereum/EthGenesisVault.sol";
import {EthPrivErc20Vault} from "../../contracts/vaults/ethereum/EthPrivErc20Vault.sol";
import {EthPrivVault} from "../../contracts/vaults/ethereum/EthPrivVault.sol";
import {EthVault, IEthVault} from "../../contracts/vaults/ethereum/EthVault.sol";
import {EthVaultFactory} from "../../contracts/vaults/ethereum/EthVaultFactory.sol";
import {IEthFoxVault, EthFoxVault} from "../../contracts/vaults/ethereum/custom/EthFoxVault.sol";
import {IEthCommunityVault, EthCommunityVault} from "../../contracts/vaults/ethereum/custom/EthCommunityVault.sol";
import {EthMetaVault} from "../../contracts/vaults/ethereum/EthMetaVault.sol";
import {EthPrivMetaVault} from "../../contracts/vaults/ethereum/EthPrivMetaVault.sol";
import {EthErc20MetaVault, IEthErc20MetaVault} from "../../contracts/vaults/ethereum/EthErc20MetaVault.sol";
import {EthPrivErc20MetaVault} from "../../contracts/vaults/ethereum/EthPrivErc20MetaVault.sol";
import {EthMetaVaultFactory} from "../../contracts/vaults/ethereum/EthMetaVaultFactory.sol";
import {SubVaultsRegistry} from "../../contracts/vaults/SubVaultsRegistry.sol";
import {SubVaultsRegistryFactory} from "../../contracts/vaults/SubVaultsRegistryFactory.sol";
import {Keeper} from "../../contracts/keeper/Keeper.sol";
import {ValidatorsConsolidationsMock} from "../../contracts/mocks/ValidatorsConsolidationsMock.sol";
import {ValidatorsHelpers} from "./ValidatorsHelpers.sol";
import {ValidatorsWithdrawalsMock} from "../../contracts/mocks/ValidatorsWithdrawalsMock.sol";
import {VaultsRegistry, IVaultsRegistry} from "../../contracts/vaults/VaultsRegistry.sol";
import {CuratorsRegistry} from "../../contracts/curators/CuratorsRegistry.sol";
import {IVaultSubVaults} from "../../contracts/interfaces/IVaultSubVaults.sol";
import {ISubVaultsRegistry} from "../../contracts/interfaces/ISubVaultsRegistry.sol";
import {ISubVaultsRegistryFactory} from "../../contracts/interfaces/ISubVaultsRegistryFactory.sol";

abstract contract EthHelpers is Test, ValidatorsHelpers {
    using stdStorage for StdStorage;

    uint256 internal constant forkBlockNumber = 26200000;
    uint256 internal constant _securityDeposit = 1e9;
    address private constant _keeper = 0x6B5815467da09DaA7DC83Db21c9239d98Bb487b5;
    address private constant _validatorsRegistry = 0x00000000219ab540356cBB839Cbe05303d7705Fa;
    address private constant _vaultsRegistry = 0x3a0008a588772446f6e656133C2D5029CC4FC20E;
    address internal constant _osToken = 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38;
    address internal constant _osTokenFlashLoans = 0xeBe12d858E55DDc5FC5A8153dC3e117824fbf5d2;
    address private constant _osTokenVaultController = 0x2A261e60FB14586B474C208b1B7AC6D0f5000306;
    address private constant _osTokenConfig = 0x287d1e2A8dE183A8bf8f2b09Fa1340fBd766eb59;
    address private constant _osTokenVaultEscrow = 0x09e84205DF7c68907e619D07aFD90143c5763605;
    address private constant _sharedMevEscrow = 0x48319f97E5Da1233c21c48b80097c0FB7a20Ff86;
    address internal constant _depositDataRegistry = 0x75AB6DdCe07556639333d3Df1eaa684F5735223e;
    address internal constant _poolEscrow = 0x2296e122c1a20Fca3CAc3371357BdAd3be0dF079;
    address internal constant _rewardEthToken = 0x20BC832ca081b91433ff6c17f85701B6e92486c5;
    address internal constant _consolidationsChecker = 0x033E5BaE5bdc459CBb7d388b41a9d62020Be810F;
    address internal constant _curatorsRegistry = 0xa23F7c8d25f4503cA4cEd84d9CC2428e8745933C;
    address internal constant _balancedCurator = 0xe01351f866C118FbD04d222f9262A470F1d44d90;
    uint256 internal constant _exitingAssetsClaimDelay = 15 hours;

    enum VaultType {
        EthVault,
        EthBlocklistVault,
        EthPrivVault,
        EthGenesisVault,
        EthErc20Vault,
        EthBlocklistErc20Vault,
        EthPrivErc20Vault,
        EthFoxVault,
        EthMetaVault,
        EthPrivMetaVault,
        EthErc20MetaVault,
        EthPrivErc20MetaVault,
        EthCommunityVault
    }

    struct ForkContracts {
        Keeper keeper;
        IEthValidatorsRegistry validatorsRegistry;
        VaultsRegistry vaultsRegistry;
        IOsTokenVaultController osTokenVaultController;
        IOsTokenConfig osTokenConfig;
        IOsTokenVaultEscrow osTokenVaultEscrow;
        ISharedMevEscrow sharedMevEscrow;
        IConsolidationsChecker consolidationsChecker;
    }

    struct MetaVaultState {
        bytes32 vaultId;
        address admin;
        address feeRecipient;
        uint16 feePercent;
        uint256 capacity;
        uint256 totalShares;
        uint256 totalAssets;
        uint256 userShares;
        uint128 queuedShares;
        uint128 unclaimedAssets;
        uint256 totalTickets;
        address subVaultsRegistry;
        address curator;
        uint128 rewardsNonce;
        address[] subVaults;
    }

    mapping(VaultType vaultType => address vaultImpl) private _vaultImplementations;
    mapping(VaultType vaultType => address vaultFactory) private _vaultFactories;
    mapping(VaultType vaultType => address vaultFactory) private _vaultPrevFactories;

    address internal _validatorsWithdrawals;
    address internal _validatorsConsolidations;
    address internal _subVaultsRegistryFactory;

    function _activateEthereumFork() internal returns (ForkContracts memory) {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), forkBlockNumber);

        _validatorsWithdrawals = address(new ValidatorsWithdrawalsMock());
        _validatorsConsolidations = address(new ValidatorsConsolidationsMock());

        // Deploy SubVaultsRegistryFactory
        address subVaultsRegistryImpl = address(
            new SubVaultsRegistry(_curatorsRegistry, _vaultsRegistry, _keeper, _osTokenVaultController, _osTokenConfig)
        );
        _subVaultsRegistryFactory =
            address(new SubVaultsRegistryFactory(subVaultsRegistryImpl, IVaultsRegistry(_vaultsRegistry)));

        return ForkContracts({
            keeper: Keeper(_keeper),
            validatorsRegistry: IEthValidatorsRegistry(_validatorsRegistry),
            vaultsRegistry: VaultsRegistry(_vaultsRegistry),
            osTokenVaultController: IOsTokenVaultController(_osTokenVaultController),
            osTokenConfig: IOsTokenConfig(_osTokenConfig),
            osTokenVaultEscrow: IOsTokenVaultEscrow(_osTokenVaultEscrow),
            sharedMevEscrow: ISharedMevEscrow(_sharedMevEscrow),
            consolidationsChecker: IConsolidationsChecker(_consolidationsChecker)
        });
    }

    function _getOrCreateVault(VaultType vaultType, address admin, bytes memory initParams, bool isOwnMevEscrow)
        internal
        returns (address vault)
    {
        vault = _getForkVault(vaultType);
        if (vault != address(0)) {
            _upgradeVault(vaultType, vault);
            if (Keeper(_keeper).isHarvestRequired(vault)) {
                IKeeperRewards.HarvestParams memory harvestParams = _setEthVaultReward(vault, 0, 0);
                IVaultState(vault).updateState(harvestParams);
            }
        } else {
            vault = _createVault(vaultType, admin, initParams, isOwnMevEscrow);
        }

        address currentAdmin = IEthVault(vault).admin();
        if (currentAdmin != admin) {
            vm.prank(currentAdmin);
            IEthVault(vault).setAdmin(admin);
        }
        // EthCommunityVault locks feeRecipient to nodesManager, skip for it
        if (vaultType != VaultType.EthCommunityVault && IEthVault(vault).feeRecipient() != admin) {
            vm.prank(admin);
            IEthVault(vault).setFeeRecipient(admin);
        }
    }

    function _getOrCreateFactory(VaultType _vaultType) internal returns (EthVaultFactory) {
        if (_vaultFactories[_vaultType] != address(0)) {
            return EthVaultFactory(_vaultFactories[_vaultType]);
        }

        address impl = _getOrCreateVaultImpl(_vaultType);
        EthVaultFactory factory = new EthVaultFactory(impl, IVaultsRegistry(_vaultsRegistry));

        _vaultFactories[_vaultType] = address(factory);

        vm.prank(VaultsRegistry(_vaultsRegistry).owner());
        VaultsRegistry(_vaultsRegistry).addFactory(address(factory));

        return factory;
    }

    function _getOrCreateMetaFactory(VaultType _vaultType) internal returns (EthMetaVaultFactory) {
        if (_vaultFactories[_vaultType] != address(0)) {
            return EthMetaVaultFactory(_vaultFactories[_vaultType]);
        }

        address impl = _getOrCreateVaultImpl(_vaultType);
        EthMetaVaultFactory factory = new EthMetaVaultFactory(impl, IVaultsRegistry(_vaultsRegistry));

        _vaultFactories[_vaultType] = address(factory);

        vm.prank(VaultsRegistry(_vaultsRegistry).owner());
        VaultsRegistry(_vaultsRegistry).addFactory(address(factory));

        return factory;
    }

    function _getPrevVersionVaultFactory(VaultType _vaultType) internal returns (EthVaultFactory) {
        if (_vaultPrevFactories[_vaultType] != address(0)) {
            return EthVaultFactory(_vaultPrevFactories[_vaultType]);
        }

        // Return actual contract addresses of previous factory versions if needed
        address impl;
        if (_vaultType == VaultType.EthVault) {
            impl = 0xDecb606ee9140f229Df78F9E40041EAD61610F8f;
        } else if (_vaultType == VaultType.EthPrivVault) {
            impl = 0x135f45e0179dd928E73422B40Bdc6C5d7047a035;
        } else if (_vaultType == VaultType.EthBlocklistVault) {
            impl = 0xd19E4B1d680a6aA672b08ebf483381bc0C9c8478;
        } else if (_vaultType == VaultType.EthErc20Vault) {
            impl = 0x7E5198DF09fED891e7AecD623cD2231443cEb5d5;
        } else if (_vaultType == VaultType.EthPrivErc20Vault) {
            impl = 0x9488A7dd178F0D927707eEc61A7D8C0ae9558c88;
        } else if (_vaultType == VaultType.EthBlocklistErc20Vault) {
            impl = 0x84d44A696539B3eF4162184fb8ab97596A311e9E;
        } else {
            return EthVaultFactory(address(0));
        }

        EthVaultFactory factory = new EthVaultFactory(impl, IVaultsRegistry(_vaultsRegistry));
        _vaultPrevFactories[_vaultType] = address(factory);

        vm.prank(VaultsRegistry(_vaultsRegistry).owner());
        VaultsRegistry(_vaultsRegistry).addFactory(address(factory));

        return factory;
    }

    function _getPrevVersionMetaVaultFactory(VaultType _vaultType) internal returns (EthMetaVaultFactory) {
        if (_vaultPrevFactories[_vaultType] != address(0)) {
            return EthMetaVaultFactory(_vaultPrevFactories[_vaultType]);
        }

        // V6 implementations of the meta vaults
        address impl;
        if (_vaultType == VaultType.EthMetaVault) {
            impl = 0xE2121568066C0a9d794bbB95D0Ade0ebd81cCaf9;
        } else if (_vaultType == VaultType.EthPrivMetaVault) {
            impl = 0xfc81D3369fBEAa6E0926eedA71E5C91724f2c079;
        } else if (_vaultType == VaultType.EthErc20MetaVault) {
            impl = 0xBb1B3E55315967c65133A0e942d8EA7a992aF6C7;
        } else if (_vaultType == VaultType.EthPrivErc20MetaVault) {
            impl = 0xD935a9f586dFa83Df20553b40Ce24f3746b258E2;
        } else {
            return EthMetaVaultFactory(address(0));
        }

        EthMetaVaultFactory factory = new EthMetaVaultFactory(impl, IVaultsRegistry(_vaultsRegistry));
        _vaultPrevFactories[_vaultType] = address(factory);

        vm.prank(VaultsRegistry(_vaultsRegistry).owner());
        VaultsRegistry(_vaultsRegistry).addFactory(address(factory));

        return factory;
    }

    function _depositToVault(address vault, uint256 amount, address from, address to) internal {
        vm.prank(from);
        IEthVault(vault).deposit{value: amount}(to, address(0));
    }

    function _collateralizeEthVault(address vault) internal {
        _collateralizeVault(_keeper, _validatorsRegistry, vault);
    }

    function _mintOsToken(address user, uint256 amount) internal {
        vm.prank(_getForkVault(VaultType.EthGenesisVault));
        IOsTokenVaultController(_osTokenVaultController).mintShares(user, amount);
    }

    function _setEthVaultReward(address vault, int160 totalReward, uint160 unlockedMevReward)
        internal
        returns (IKeeperRewards.HarvestParams memory harvestParams)
    {
        (totalReward, unlockedMevReward) = _getVaultRewards(vault, totalReward, unlockedMevReward);
        SetVaultRewardParams memory params = SetVaultRewardParams({
            keeper: _keeper,
            osTokenCtrl: _osTokenVaultController,
            vault: vault,
            totalReward: totalReward,
            unlockedMevReward: unlockedMevReward
        });
        return _setVaultReward(params);
    }

    function _registerEthValidator(address vault, uint256 depositAmount, bool isV1Validator)
        internal
        returns (bytes memory publicKey)
    {
        return _registerValidator(_keeper, _validatorsRegistry, vault, depositAmount, isV1Validator);
    }

    function _getEthValidatorApproval(address vault, uint256 depositAmount, string memory ipfsHash, bool isV1Validator)
        internal
        view
        returns (IKeeperValidators.ApprovalParams memory harvestParams)
    {
        uint256[] memory deposits = new uint256[](1);
        deposits[0] = depositAmount / 1 gwei;

        harvestParams = _getValidatorsApproval(_keeper, _validatorsRegistry, vault, ipfsHash, deposits, isV1Validator);
    }

    function _startSnapshotGas(string memory label) internal {
        if (vm.envBool("TEST_SKIP_SNAPSHOTS")) return;
        return vm.startSnapshotGas(label);
    }

    function _stopSnapshotGas() internal {
        if (vm.envBool("TEST_SKIP_SNAPSHOTS")) return;
        vm.stopSnapshotGas();
    }

    function _getForkVault(VaultType vaultType) internal view returns (address) {
        if (vaultType == VaultType.EthGenesisVault) {
            return 0xAC0F906E433d58FA868F936E8A43230473652885;
        } else if (vaultType == VaultType.EthFoxVault) {
            return 0x4FEF9D741011476750A243aC70b9789a63dd47Df;
        }

        if (!vm.envBool("TEST_USE_FORK_VAULTS")) return address(0);

        // Update with actual deployed vault addresses for each type
        if (vaultType == VaultType.EthVault) {
            return 0x7Eed3ea8D83ba4Ccc1b20674F46825ece2fce594;
        } else if (vaultType == VaultType.EthPrivVault) {
            return 0xD66A71A68392767F26b7EE47e9a0293191A23072;
        } else if (vaultType == VaultType.EthErc20Vault) {
            return 0x9c29c571847A68A947AceC8bacd303e36bC72ec5;
        } else if (vaultType == VaultType.EthPrivErc20Vault) {
            return 0xFB22Ded2bd69aff0907e195F23E448aB44E3cA97;
        } else if (vaultType == VaultType.EthBlocklistVault) {
            return 0xf51033647a8ab632B80B69b1c680aaDcC8ADa048;
        } else if (vaultType == VaultType.EthBlocklistErc20Vault) {
            return 0x498399e4f5FDe641a43DCEAFc0aac858abaF2034;
        } else if (vaultType == VaultType.EthMetaVault) {
            return 0x5543be81786d11EAF656b742BaD92065f329Ada7;
        } else if (vaultType == VaultType.EthPrivMetaVault) {
            return 0x20C949a75cFb19Ec6D07bC203C79a08D05881AEc;
        } else if (vaultType == VaultType.EthErc20MetaVault) {
            return 0x3dc69Bdc22119961Dfdf82242113F2689D7e5402;
        } else if (vaultType == VaultType.EthPrivErc20MetaVault) {
            return 0x1667b85a5E6D3ba4696Aa5c45EdB491D6548E7C9;
        }
        return address(0);
    }

    function _getVaultRewards(address vault, int160 newTotalReward, uint160 newUnlockedMevReward)
        private
        view
        returns (int160, uint160)
    {
        // Update with actual values if needed for specific vaults
        if (vault == 0xAC0F906E433d58FA868F936E8A43230473652885) {
            // Genesis Vault
            newTotalReward += 18480813404056629887731;
            newUnlockedMevReward += 1159246693651327328198;
        } else if (vault == 0x4FEF9D741011476750A243aC70b9789a63dd47Df) {
            newTotalReward += 2303473324606000000000;
        }

        if (!vm.envBool("TEST_USE_FORK_VAULTS")) {
            return (newTotalReward, newUnlockedMevReward);
        }

        // Add specific rewards for each vault type
        if (vault == 0x7Eed3ea8D83ba4Ccc1b20674F46825ece2fce594) {
            newTotalReward += 1835140592094467096;
            newUnlockedMevReward += 246577230094467096;
        } else if (vault == 0xD66A71A68392767F26b7EE47e9a0293191A23072) {
            newTotalReward += 17651468000000000;
        } else if (vault == 0x9c29c571847A68A947AceC8bacd303e36bC72ec5) {
            newTotalReward += 1590862592749045978;
            newUnlockedMevReward += 251734367749045978;
        }

        return (newTotalReward, newUnlockedMevReward);
    }

    function _createVault(VaultType vaultType, address admin, bytes memory initParams, bool isOwnMevEscrow)
        internal
        returns (address)
    {
        if (vaultType == VaultType.EthFoxVault) {
            address vaultImpl = _getOrCreateVaultImpl(vaultType);
            address vault = address(new ERC1967Proxy(vaultImpl, ""));
            vm.deal(address(this), 1 ether);
            IEthVault(vault).initialize{value: _securityDeposit}(initParams);
            vm.prank(VaultsRegistry(_vaultsRegistry).owner());
            VaultsRegistry(_vaultsRegistry).addVault(vault);
            return vault;
        }

        if (vaultType == VaultType.EthCommunityVault) {
            address vaultImpl = _getOrCreateVaultImpl(vaultType);
            address vault = address(new ERC1967Proxy(vaultImpl, ""));
            vm.deal(address(this), 1 ether);
            IEthErc20Vault(vault).initialize{value: _securityDeposit}(initParams);
            vm.prank(VaultsRegistry(_vaultsRegistry).owner());
            VaultsRegistry(_vaultsRegistry).addVault(vault);
            return vault;
        }

        address vaultAddress;
        if (
            vaultType == VaultType.EthMetaVault || vaultType == VaultType.EthPrivMetaVault
                || vaultType == VaultType.EthErc20MetaVault || vaultType == VaultType.EthPrivErc20MetaVault
        ) {
            EthMetaVaultFactory factory = _getOrCreateMetaFactory(vaultType);
            vm.deal(admin, admin.balance + _securityDeposit);
            vm.prank(admin);
            vaultAddress = factory.createVault{value: _securityDeposit}(initParams);
        } else {
            EthVaultFactory factory = _getOrCreateFactory(vaultType);
            vm.deal(admin, admin.balance + _securityDeposit);
            vm.prank(admin);
            vaultAddress = factory.createVault{value: _securityDeposit}(initParams, isOwnMevEscrow);
        }

        return vaultAddress;
    }

    function _createPrevVersionVault(VaultType vaultType, address admin, bytes memory initParams, bool isOwnMevEscrow)
        internal
        returns (address vaultAddress)
    {
        vm.deal(admin, admin.balance + _securityDeposit);
        if (
            vaultType == VaultType.EthMetaVault || vaultType == VaultType.EthPrivMetaVault
                || vaultType == VaultType.EthErc20MetaVault || vaultType == VaultType.EthPrivErc20MetaVault
        ) {
            EthMetaVaultFactory metaFactory = _getPrevVersionMetaVaultFactory(vaultType);
            vm.prank(admin);
            return metaFactory.createVault{value: _securityDeposit}(initParams);
        }

        EthVaultFactory factory = _getPrevVersionVaultFactory(vaultType);
        vm.prank(admin);
        vaultAddress = factory.createVault{value: _securityDeposit}(initParams, isOwnMevEscrow);
    }

    function _createV1EthVault(address admin, bytes memory initParams, bool isOwnMevEscrow) internal returns (address) {
        EthVaultFactory factory = EthVaultFactory(0xDada5a8E3703B1e3EA2bAe5Ab704627eb2659fCC);

        vm.prank(VaultsRegistry(_vaultsRegistry).owner());
        VaultsRegistry(_vaultsRegistry).addFactory(address(factory));

        vm.deal(admin, admin.balance + _securityDeposit);
        vm.prank(admin);
        address vaultAddress = factory.createVault{value: _securityDeposit}(initParams, isOwnMevEscrow);

        return vaultAddress;
    }

    function _upgradeVault(VaultType vaultType, address vault) internal {
        EthVault vaultContract = EthVault(payable(vault));
        uint256 currentVersion = vaultContract.version();

        if (vaultType == VaultType.EthFoxVault) {
            if (currentVersion == 2) return;
            require(currentVersion == 1, "Invalid vault version");
        } else if (vaultType == VaultType.EthCommunityVault) {
            if (currentVersion == 6) return;
            revert("EthCommunityVault does not support upgrades");
        } else if (
            vaultType == VaultType.EthMetaVault || vaultType == VaultType.EthPrivMetaVault
                || vaultType == VaultType.EthErc20MetaVault || vaultType == VaultType.EthPrivErc20MetaVault
        ) {
            if (currentVersion == 7) return;
            require(currentVersion == 6, "Invalid vault version");
        } else {
            if (currentVersion == 5) return;
            require(currentVersion == 4, "Invalid vault version");
        }

        address newImpl = _getOrCreateVaultImpl(vaultType);
        address admin = vaultContract.admin();

        vm.deal(admin, admin.balance + 1 ether);
        vm.prank(admin);
        vaultContract.upgradeToAndCall(newImpl, "");
    }

    function _getOrCreateVaultImpl(VaultType _vaultType) internal returns (address impl) {
        if (_vaultImplementations[_vaultType] != address(0)) {
            return _vaultImplementations[_vaultType];
        }

        IEthVault.EthVaultConstructorArgs memory ethArgs = IEthVault.EthVaultConstructorArgs(
            _keeper,
            _vaultsRegistry,
            _validatorsRegistry,
            _validatorsWithdrawals,
            _validatorsConsolidations,
            _consolidationsChecker,
            _osTokenVaultController,
            _osTokenConfig,
            _osTokenVaultEscrow,
            _sharedMevEscrow,
            _depositDataRegistry,
            uint64(_exitingAssetsClaimDelay)
        );

        IEthErc20Vault.EthErc20VaultConstructorArgs memory ethErc20Args = IEthErc20Vault.EthErc20VaultConstructorArgs(
            _keeper,
            _vaultsRegistry,
            _validatorsRegistry,
            _validatorsWithdrawals,
            _validatorsConsolidations,
            _consolidationsChecker,
            _osTokenVaultController,
            _osTokenConfig,
            _osTokenVaultEscrow,
            _sharedMevEscrow,
            _depositDataRegistry,
            uint64(_exitingAssetsClaimDelay)
        );

        if (_vaultType == VaultType.EthVault) {
            impl = address(new EthVault(ethArgs));
        } else if (_vaultType == VaultType.EthBlocklistVault) {
            impl = address(new EthBlocklistVault(ethArgs));
        } else if (_vaultType == VaultType.EthPrivVault) {
            impl = address(new EthPrivVault(ethArgs));
        } else if (_vaultType == VaultType.EthGenesisVault) {
            impl = address(new EthGenesisVault(ethArgs, _poolEscrow, _rewardEthToken));
        } else if (_vaultType == VaultType.EthErc20Vault) {
            impl = address(new EthErc20Vault(ethErc20Args));
        } else if (_vaultType == VaultType.EthBlocklistErc20Vault) {
            impl = address(new EthBlocklistErc20Vault(ethErc20Args));
        } else if (_vaultType == VaultType.EthPrivErc20Vault) {
            impl = address(new EthPrivErc20Vault(ethErc20Args));
        } else if (_vaultType == VaultType.EthCommunityVault) {
            impl = address(new EthCommunityVault(ethErc20Args));
        } else if (_vaultType == VaultType.EthFoxVault) {
            IEthFoxVault.EthFoxVaultConstructorArgs memory ethFoxVaultArgs = IEthFoxVault.EthFoxVaultConstructorArgs(
                _keeper,
                _vaultsRegistry,
                _validatorsRegistry,
                _validatorsWithdrawals,
                _validatorsConsolidations,
                _consolidationsChecker,
                _sharedMevEscrow,
                _depositDataRegistry,
                uint64(_exitingAssetsClaimDelay)
            );
            impl = address(new EthFoxVault(ethFoxVaultArgs));
        } else if (_vaultType == VaultType.EthMetaVault || _vaultType == VaultType.EthPrivMetaVault) {
            IEthMetaVault.EthMetaVaultConstructorArgs memory ethMetaVaultArgs = IEthMetaVault.EthMetaVaultConstructorArgs(
                _keeper,
                _vaultsRegistry,
                _osTokenVaultController,
                _osTokenConfig,
                _osTokenVaultEscrow,
                _subVaultsRegistryFactory,
                uint64(_exitingAssetsClaimDelay)
            );
            impl = _vaultType == VaultType.EthMetaVault
                ? address(new EthMetaVault(ethMetaVaultArgs))
                : address(new EthPrivMetaVault(ethMetaVaultArgs));
        } else if (_vaultType == VaultType.EthErc20MetaVault || _vaultType == VaultType.EthPrivErc20MetaVault) {
            IEthErc20MetaVault.EthErc20MetaVaultConstructorArgs memory ethErc20MetaVaultArgs =
                IEthErc20MetaVault.EthErc20MetaVaultConstructorArgs(
                    _keeper,
                    _vaultsRegistry,
                    _osTokenVaultController,
                    _osTokenConfig,
                    _osTokenVaultEscrow,
                    _subVaultsRegistryFactory,
                    uint64(_exitingAssetsClaimDelay)
                );
            impl = _vaultType == VaultType.EthErc20MetaVault
                ? address(new EthErc20MetaVault(ethErc20MetaVaultArgs))
                : address(new EthPrivErc20MetaVault(ethErc20MetaVaultArgs));
        } else {
            revert("Unsupported vault type");
        }

        _vaultImplementations[_vaultType] = impl;

        vm.prank(VaultsRegistry(_vaultsRegistry).owner());
        VaultsRegistry(_vaultsRegistry).addVaultImpl(impl);

        return impl;
    }

    // ============ Shared Meta Vault Test Helpers ============

    function _getEmptyHarvestParams() internal pure returns (IKeeperRewards.HarvestParams memory) {
        bytes32[] memory emptyProof;
        return
            IKeeperRewards.HarvestParams({rewardsRoot: bytes32(0), proof: emptyProof, reward: 0, unlockedMevReward: 0});
    }

    function _setVaultRewardsNonce(address vault, uint64 rewardsNonce) internal {
        stdstore.enable_packed_slots().target(_keeper).sig("rewards(address)").with_key(vault).depth(1)
            .checked_write(rewardsNonce);
    }

    function _setKeeperRewardsNonce(uint64 rewardsNonce) internal {
        stdstore.enable_packed_slots().target(_keeper).sig("rewardsNonce()").checked_write(rewardsNonce);
    }

    function _getSubVaultsRegistry(address vault) internal view returns (ISubVaultsRegistry) {
        return ISubVaultsRegistry(IVaultSubVaults(vault).subVaultsRegistry());
    }

    function _createEthSubVault(address _admin) internal returns (address) {
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 5,
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );

        return _createVault(VaultType.EthVault, _admin, initParams, false);
    }

    // ============ Meta Vault Upgrade Test Helpers ============

    function _createPrevVersionMetaVault(
        VaultType vaultType,
        address admin,
        bytes memory initParams,
        uint256 subVaultsCount
    ) internal returns (address vault) {
        vault = _createPrevVersionVault(vaultType, admin, initParams, false);

        ISubVaultsRegistry registry = _getSubVaultsRegistry(vault);
        for (uint256 i = 0; i < subVaultsCount; i++) {
            address subVault = _createEthSubVault(admin);
            _collateralizeEthVault(subVault);

            vm.prank(admin);
            registry.addSubVault(subVault);
        }
    }

    function _upgradeMetaVaultAndCheckState(VaultType vaultType, address vault, address user) internal {
        IEthMetaVault metaVault = IEthMetaVault(vault);
        ISubVaultsRegistry registry = _getSubVaultsRegistry(vault);
        assertEq(metaVault.version(), 6, "Vault should be version 6 before upgrade");

        // record state before upgrade
        MetaVaultState memory stateBefore = _getMetaVaultState(vault, user);
        ISubVaultsRegistry.SubVaultState[] memory subVaultStatesBefore =
            new ISubVaultsRegistry.SubVaultState[](stateBefore.subVaults.length);
        for (uint256 i = 0; i < stateBefore.subVaults.length; i++) {
            subVaultStatesBefore[i] = registry.subVaultsStates(stateBefore.subVaults[i]);
        }

        // deploy the new implementation upfront, so that its events don't interfere with the expected one
        _getOrCreateVaultImpl(vaultType);

        // the v7 initializer upgrades the SubVaultsRegistry proxy in place
        vm.expectEmit(address(registry));
        emit IERC1967.Upgraded(ISubVaultsRegistryFactory(_subVaultsRegistryFactory).implementation());
        _upgradeVault(vaultType, vault);

        assertEq(metaVault.version(), 7, "Vault should be version 7 after upgrade");
        assertEq(metaVault.vaultId(), stateBefore.vaultId, "Vault ID should be preserved");

        // vault state is preserved
        MetaVaultState memory stateAfter = _getMetaVaultState(vault, user);
        assertEq(stateAfter.admin, stateBefore.admin, "Admin should be preserved");
        assertEq(stateAfter.feeRecipient, stateBefore.feeRecipient, "Fee recipient should be preserved");
        assertEq(stateAfter.feePercent, stateBefore.feePercent, "Fee percent should be preserved");
        assertEq(stateAfter.capacity, stateBefore.capacity, "Capacity should be preserved");
        assertEq(stateAfter.totalShares, stateBefore.totalShares, "Total shares should be preserved");
        assertEq(stateAfter.totalAssets, stateBefore.totalAssets, "Total assets should be preserved");
        assertEq(stateAfter.userShares, stateBefore.userShares, "User shares should be preserved");
        assertEq(stateAfter.queuedShares, stateBefore.queuedShares, "Queued shares should be preserved");
        assertEq(stateAfter.unclaimedAssets, stateBefore.unclaimedAssets, "Unclaimed assets should be preserved");
        assertEq(stateAfter.totalTickets, stateBefore.totalTickets, "Total tickets should be preserved");

        // registry state is preserved
        assertEq(stateAfter.subVaultsRegistry, stateBefore.subVaultsRegistry, "Registry should be preserved");
        assertEq(registry.metaVault(), vault, "Registry meta vault should be preserved");
        assertEq(stateAfter.curator, stateBefore.curator, "Curator should be preserved");
        assertEq(stateAfter.rewardsNonce, stateBefore.rewardsNonce, "Rewards nonce should be preserved");
        assertEq(stateAfter.subVaults, stateBefore.subVaults, "Sub vaults should be preserved");
        for (uint256 i = 0; i < stateBefore.subVaults.length; i++) {
            ISubVaultsRegistry.SubVaultState memory subVaultState = registry.subVaultsStates(stateBefore.subVaults[i]);
            assertEq(
                subVaultState.stakedShares, subVaultStatesBefore[i].stakedShares, "Staked shares should be preserved"
            );
            assertEq(
                subVaultState.queuedShares, subVaultStatesBefore[i].queuedShares, "Queued shares should be preserved"
            );
        }

        // the upgrade cannot be executed twice
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        metaVault.initialize("");
    }

    function _getMetaVaultState(address vault, address user) private view returns (MetaVaultState memory state) {
        IEthMetaVault metaVault = IEthMetaVault(vault);
        ISubVaultsRegistry registry = _getSubVaultsRegistry(vault);

        state.vaultId = metaVault.vaultId();
        state.admin = metaVault.admin();
        state.feeRecipient = metaVault.feeRecipient();
        state.feePercent = metaVault.feePercent();
        state.capacity = metaVault.capacity();
        state.totalShares = metaVault.totalShares();
        state.totalAssets = metaVault.totalAssets();
        state.userShares = metaVault.getShares(user);
        (state.queuedShares, state.unclaimedAssets,,, state.totalTickets) = metaVault.getExitQueueData();
        state.subVaultsRegistry = address(registry);
        state.curator = registry.subVaultsCurator();
        state.rewardsNonce = registry.subVaultsRewardsNonce();
        state.subVaults = registry.getSubVaults();
    }
}
