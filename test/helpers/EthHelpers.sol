// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Test, stdStorage, StdStorage} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IKeeperValidators} from "../../contracts/interfaces/IKeeperValidators.sol";
import {IOsTokenConfig} from "../../contracts/interfaces/IOsTokenConfig.sol";
import {IOsTokenVaultController} from "../../contracts/interfaces/IOsTokenVaultController.sol";
import {IOsTokenVaultEscrow} from "../../contracts/interfaces/IOsTokenVaultEscrow.sol";
import {ISharedMevEscrow} from "../../contracts/interfaces/ISharedMevEscrow.sol";
import {IEthValidatorsRegistry} from "../../contracts/interfaces/IEthValidatorsRegistry.sol";
import {IKeeperRewards} from "../../contracts/interfaces/IKeeperRewards.sol";
import {IVaultState} from "../../contracts/interfaces/IVaultState.sol";
import {IMetaVault} from "../../contracts/interfaces/IMetaVault.sol";
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
import {EthMetaVault} from "../../contracts/vaults/ethereum/EthMetaVault.sol";
import {EthPrivMetaVault} from "../../contracts/vaults/ethereum/EthPrivMetaVault.sol";
import {EthMetaVaultFactory} from "../../contracts/vaults/ethereum/EthMetaVaultFactory.sol";
import {Keeper} from "../../contracts/keeper/Keeper.sol";
import {ValidatorsConsolidationsMock} from "../../contracts/mocks/ValidatorsConsolidationsMock.sol";
import {ValidatorsHelpers} from "./ValidatorsHelpers.sol";
import {ValidatorsWithdrawalsMock} from "../../contracts/mocks/ValidatorsWithdrawalsMock.sol";
import {VaultsRegistry, IVaultsRegistry} from "../../contracts/vaults/VaultsRegistry.sol";
import {CuratorsRegistry} from "../../contracts/curators/CuratorsRegistry.sol";

abstract contract EthHelpers is Test, ValidatorsHelpers {
    using stdStorage for StdStorage;

    uint256 internal constant forkBlockNumber = 24235110;
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
    address internal constant _balancedCurator = 0xD30E7e4bDbd396cfBe72Ad2f4856769C54eA6b0b;
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
        EthPrivMetaVault
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

    mapping(VaultType vaultType => address vaultImpl) private _vaultImplementations;
    mapping(VaultType vaultType => address vaultFactory) private _vaultFactories;
    mapping(VaultType vaultType => address vaultFactory) private _vaultPrevFactories;

    address internal _validatorsWithdrawals;
    address internal _validatorsConsolidations;

    function _activateEthereumFork() internal returns (ForkContracts memory) {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), forkBlockNumber);

        _validatorsWithdrawals = address(new ValidatorsWithdrawalsMock());
        _validatorsConsolidations = address(new ValidatorsConsolidationsMock());

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
        if (IEthVault(vault).feeRecipient() != admin) {
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
        } else if (_vaultType == VaultType.EthMetaVault) {
            impl = 0xD0D527B67186d8880f9427ea4Cf9847E89bcE764;
        } else {
            return EthVaultFactory(address(0));
        }

        EthVaultFactory factory = new EthVaultFactory(impl, IVaultsRegistry(_vaultsRegistry));
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
            return 0x34284C27A2304132aF751b0dEc5bBa2CF98eD039;
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
            newTotalReward += 15357936244318545414766;
            newUnlockedMevReward += 954581796972242855233;
        } else if (vault == 0x4FEF9D741011476750A243aC70b9789a63dd47Df) {
            newTotalReward += 1097049381115000000000;
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

        address vaultAddress;
        if (vaultType == VaultType.EthMetaVault) {
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
        returns (address)
    {
        EthVaultFactory factory = _getPrevVersionVaultFactory(vaultType);

        vm.deal(admin, admin.balance + _securityDeposit);
        vm.prank(admin);
        address vaultAddress = factory.createVault{value: _securityDeposit}(initParams, isOwnMevEscrow);

        return vaultAddress;
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
        } else if (vaultType == VaultType.EthMetaVault || vaultType == VaultType.EthPrivMetaVault) {
            if (currentVersion == 6) return;
            require(currentVersion == 5, "Invalid vault version");
        } else {
            if (currentVersion == 5) return;
            require(currentVersion == 4, "Invalid vault version");
        }

        address newImpl = _getOrCreateVaultImpl(vaultType);
        address admin = vaultContract.admin();

        vm.deal(admin, admin.balance + 1 ether);
        vm.prank(admin);
        vaultContract.upgradeToAndCall(newImpl, "0x");
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
        } else if (_vaultType == VaultType.EthMetaVault) {
            IMetaVault.MetaVaultConstructorArgs memory ethMetaVaultArgs = IMetaVault.MetaVaultConstructorArgs(
                _keeper,
                _vaultsRegistry,
                _osTokenVaultController,
                _osTokenConfig,
                _osTokenVaultEscrow,
                _curatorsRegistry,
                uint64(_exitingAssetsClaimDelay)
            );
            impl = address(new EthMetaVault(ethMetaVaultArgs));
        } else if (_vaultType == VaultType.EthPrivMetaVault) {
            IMetaVault.MetaVaultConstructorArgs memory ethMetaVaultArgs = IMetaVault.MetaVaultConstructorArgs(
                _keeper,
                _vaultsRegistry,
                _osTokenVaultController,
                _osTokenConfig,
                _osTokenVaultEscrow,
                _curatorsRegistry,
                uint64(_exitingAssetsClaimDelay)
            );
            impl = address(new EthPrivMetaVault(ethMetaVaultArgs));
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
        stdstore.enable_packed_slots().target(_keeper).sig("rewards(address)").with_key(vault).depth(1).checked_write(
            rewardsNonce
        );
    }

    function _setKeeperRewardsNonce(uint64 rewardsNonce) internal {
        stdstore.enable_packed_slots().target(_keeper).sig("rewardsNonce()").checked_write(rewardsNonce);
    }
}
