// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {IKeeperValidators} from "../../contracts/interfaces/IKeeperValidators.sol";
import {IOsTokenConfig} from "../../contracts/interfaces/IOsTokenConfig.sol";
import {IOsTokenVaultController} from "../../contracts/interfaces/IOsTokenVaultController.sol";
import {IOsTokenVaultEscrow} from "../../contracts/interfaces/IOsTokenVaultEscrow.sol";
import {ISharedMevEscrow} from "../../contracts/interfaces/ISharedMevEscrow.sol";
import {IEthValidatorsRegistry} from "../../contracts/interfaces/IEthValidatorsRegistry.sol";
import {IKeeperRewards} from "../../contracts/interfaces/IKeeperRewards.sol";
import {IVaultState} from "../../contracts/interfaces/IVaultState.sol";
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
import {EthFoxVault} from "../../contracts/vaults/ethereum/custom/EthFoxVault.sol";
import {Keeper} from "../../contracts/keeper/Keeper.sol";
import {ValidatorsConsolidationsMock} from "../../contracts/mocks/ValidatorsConsolidationsMock.sol";
import {ValidatorsHelpers} from "./ValidatorsHelpers.sol";
import {ValidatorsWithdrawalsMock} from "../../contracts/mocks/ValidatorsWithdrawalsMock.sol";
import {VaultsRegistry, IVaultsRegistry} from "../../contracts/vaults/VaultsRegistry.sol";

abstract contract EthHelpers is Test, ValidatorsHelpers {
    uint256 internal constant forkBlockNumber = 22100000;
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
    uint256 internal constant _exitingAssetsClaimDelay = 1 days;

    enum VaultType {
        EthVault,
        EthBlocklistVault,
        EthPrivVault,
        EthGenesisVault,
        EthErc20Vault,
        EthBlocklistErc20Vault,
        EthPrivErc20Vault,
        EthFoxVault
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

    address internal _consolidationsChecker;
    address internal _validatorsWithdrawals;
    address internal _validatorsConsolidations;

    function _activateEthereumFork() internal returns (ForkContracts memory) {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), forkBlockNumber);

        _validatorsWithdrawals = address(new ValidatorsWithdrawalsMock());
        _validatorsConsolidations = address(new ValidatorsConsolidationsMock());
        _consolidationsChecker = address(new ConsolidationsChecker(address(_keeper)));

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
            return 0x8A93A876912c9F03F88Bc9114847cf5b63c89f56;
        } else if (vaultType == VaultType.EthPrivVault) {
            return 0xD66A71A68392767F26b7EE47e9a0293191A23072;
        } else if (vaultType == VaultType.EthErc20Vault) {
            return 0x7106FA765d45dF6d5340972C58742fC54f0d1Ef9;
        } else if (vaultType == VaultType.EthPrivErc20Vault) {
            return 0xFB22Ded2bd69aff0907e195F23E448aB44E3cA97;
        } else if (vaultType == VaultType.EthFoxVault) {
            return 0x4FEF9D741011476750A243aC70b9789a63dd47Df;
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
            newTotalReward += 11492988394536925432019;
            newUnlockedMevReward += 588134256533622872486;
        } else if (vault == 0x4FEF9D741011476750A243aC70b9789a63dd47Df) {
            newTotalReward += 242948554351000000000;
        }

        if (!vm.envBool("TEST_USE_FORK_VAULTS")) {
            return (newTotalReward, newUnlockedMevReward);
        }

        // Add specific rewards for each vault type
        if (vault == 0x8A93A876912c9F03F88Bc9114847cf5b63c89f56) {
            newTotalReward += 39158842473943927643;
            newUnlockedMevReward += 6210915181493109989;
        } else if (vault == 0xD66A71A68392767F26b7EE47e9a0293191A23072) {
            newTotalReward += 17651468000000000;
        }

        return (newTotalReward, newUnlockedMevReward);
    }

    function _createVault(VaultType vaultType, address admin, bytes memory initParams, bool isOwnMevEscrow)
        internal
        returns (address)
    {
        EthVaultFactory factory = _getOrCreateFactory(vaultType);

        vm.deal(admin, admin.balance + _securityDeposit);
        vm.prank(admin);
        address vaultAddress = factory.createVault{value: _securityDeposit}(initParams, isOwnMevEscrow);

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

    function _createV1EthVault(address admin, bytes memory initParams, bool isOwnMevEscrow)
        internal
        returns (address)
    {
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
            impl = address(
                new EthFoxVault(
                    _keeper,
                    _vaultsRegistry,
                    _validatorsRegistry,
                    _validatorsWithdrawals,
                    _validatorsConsolidations,
                    _consolidationsChecker,
                    _sharedMevEscrow,
                    _depositDataRegistry,
                    _exitingAssetsClaimDelay
                )
            );
        }

        _vaultImplementations[_vaultType] = impl;

        vm.prank(VaultsRegistry(_vaultsRegistry).owner());
        VaultsRegistry(_vaultsRegistry).addVaultImpl(impl);

        return impl;
    }
}
