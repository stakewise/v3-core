// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IKeeperValidators} from "../../contracts/interfaces/IKeeperValidators.sol";
import {IOsTokenConfig} from "../../contracts/interfaces/IOsTokenConfig.sol";
import {IOsTokenVaultController} from "../../contracts/interfaces/IOsTokenVaultController.sol";
import {IOsTokenVaultEscrow} from "../../contracts/interfaces/IOsTokenVaultEscrow.sol";
import {ISharedMevEscrow} from "../../contracts/interfaces/ISharedMevEscrow.sol";
import {IGnoValidatorsRegistry} from "../../contracts/interfaces/IGnoValidatorsRegistry.sol";
import {IKeeperRewards} from "../../contracts/interfaces/IKeeperRewards.sol";
import {IVaultState} from "../../contracts/interfaces/IVaultState.sol";
import {IConsolidationsChecker} from "../../contracts/interfaces/IConsolidationsChecker.sol";
import {ConsolidationsChecker} from "../../contracts/validators/ConsolidationsChecker.sol";
import {GnoBlocklistErc20Vault} from "../../contracts/vaults/gnosis/GnoBlocklistErc20Vault.sol";
import {GnoBlocklistVault} from "../../contracts/vaults/gnosis/GnoBlocklistVault.sol";
import {GnoErc20Vault, IGnoErc20Vault} from "../../contracts/vaults/gnosis/GnoErc20Vault.sol";
import {GnoGenesisVault} from "../../contracts/vaults/gnosis/GnoGenesisVault.sol";
import {GnoPrivErc20Vault} from "../../contracts/vaults/gnosis/GnoPrivErc20Vault.sol";
import {GnoPrivVault} from "../../contracts/vaults/gnosis/GnoPrivVault.sol";
import {GnoVault, IGnoVault} from "../../contracts/vaults/gnosis/GnoVault.sol";
import {IGnoMetaVault, GnoMetaVault} from "../../contracts/vaults/gnosis/custom/GnoMetaVault.sol";
import {GnoMetaVaultFactory} from "../../contracts/vaults/gnosis/custom/GnoMetaVaultFactory.sol";
import {GnoVaultFactory} from "../../contracts/vaults/gnosis/GnoVaultFactory.sol";
import {Keeper} from "../../contracts/keeper/Keeper.sol";
import {ValidatorsConsolidationsMock} from "../../contracts/mocks/ValidatorsConsolidationsMock.sol";
import {ValidatorsWithdrawalsMock} from "../../contracts/mocks/ValidatorsWithdrawalsMock.sol";
import {VaultsRegistry, IVaultsRegistry} from "../../contracts/vaults/VaultsRegistry.sol";
import {CuratorsRegistry} from "../../contracts/curators/CuratorsRegistry.sol";
import {ValidatorsHelpers} from "./ValidatorsHelpers.sol";

interface IGnoToken {
    function mint(address _to, uint256 _amount) external returns (bool);
    function owner() external view returns (address);
}

abstract contract GnoHelpers is Test, ValidatorsHelpers {
    uint256 internal constant forkBlockNumber = 40107000;
    uint256 internal constant _securityDeposit = 1e9;
    address private constant _keeper = 0xcAC0e3E35d3BA271cd2aaBE688ac9DB1898C26aa;
    address private constant _validatorsRegistry = 0x0B98057eA310F4d31F2a452B414647007d1645d9;
    address private constant _vaultsRegistry = 0x7d014B3C6ee446563d4e0cB6fBD8C3D0419867cB;
    address private constant _osTokenVaultController = 0x60B2053d7f2a0bBa70fe6CDd88FB47b579B9179a;
    address private constant _osTokenConfig = 0xd6672fbE1D28877db598DC0ac2559A15745FC3ec;
    address private constant _osTokenVaultEscrow = 0x28F325dD287a5984B754d34CfCA38af3A8429e71;
    address private constant _sharedMevEscrow = 0x30db0d10d3774e78f8cB214b9e8B72D4B402488a;
    address internal constant _depositDataRegistry = 0x58e16621B5c0786D6667D2d54E28A20940269E16;
    address private constant _gnoToken = 0x9C58BAcC331c9aa871AFD802DB6379a98e80CEdb;
    address internal constant _poolEscrow = 0xfc9B67b6034F6B306EA9Bd8Ec1baf3eFA2490394;
    address internal constant _rewardGnoToken = 0x6aC78efae880282396a335CA2F79863A1e6831D4;
    address private constant _sDaiToken = 0xaf204776c7245bF4147c2612BF6e5972Ee483701;
    address internal constant _tokensConverterFactory = 0x686d93989EC722560D00dC0dA31Ba69C00BfdfbF;
    uint256 internal constant _exitingAssetsClaimDelay = 1 days;

    enum VaultType {
        GnoVault,
        GnoBlocklistVault,
        GnoPrivVault,
        GnoGenesisVault,
        GnoErc20Vault,
        GnoBlocklistErc20Vault,
        GnoPrivErc20Vault,
        GnoMetaVault
    }

    struct ForkContracts {
        Keeper keeper;
        IGnoValidatorsRegistry validatorsRegistry;
        VaultsRegistry vaultsRegistry;
        IOsTokenVaultController osTokenVaultController;
        IOsTokenConfig osTokenConfig;
        IOsTokenVaultEscrow osTokenVaultEscrow;
        ISharedMevEscrow sharedMevEscrow;
        IERC20 gnoToken;
        IERC20 sdaiToken;
        IConsolidationsChecker consolidationsChecker;
    }

    mapping(VaultType vaultType => address vaultImpl) private _vaultImplementations;
    mapping(VaultType vaultType => address vaultFactory) private _vaultFactories;

    address private _consolidationsChecker;
    address private _validatorsWithdrawals;
    address private _validatorsConsolidations;
    address internal _curatorsRegistry;

    function _activateGnosisFork() internal returns (ForkContracts memory) {
        vm.createSelectFork(vm.envString("GNOSIS_RPC_URL"), forkBlockNumber);

        _validatorsWithdrawals = address(new ValidatorsWithdrawalsMock());
        _validatorsConsolidations = address(new ValidatorsConsolidationsMock());
        _consolidationsChecker = address(new ConsolidationsChecker(address(_keeper)));
        _curatorsRegistry = address(new CuratorsRegistry());

        return ForkContracts({
            keeper: Keeper(_keeper),
            validatorsRegistry: IGnoValidatorsRegistry(_validatorsRegistry),
            vaultsRegistry: VaultsRegistry(_vaultsRegistry),
            osTokenVaultController: IOsTokenVaultController(_osTokenVaultController),
            osTokenConfig: IOsTokenConfig(_osTokenConfig),
            osTokenVaultEscrow: IOsTokenVaultEscrow(_osTokenVaultEscrow),
            sharedMevEscrow: ISharedMevEscrow(_sharedMevEscrow),
            gnoToken: IERC20(_gnoToken),
            sdaiToken: IERC20(_sDaiToken),
            consolidationsChecker: IConsolidationsChecker(_consolidationsChecker)
        });
    }

    function _mintGnoToken(address to, uint256 amount) internal {
        vm.prank(IGnoToken(_gnoToken).owner());
        IGnoToken(_gnoToken).mint(to, amount);
    }

    function _depositToVault(address vault, uint256 amount, address from, address to) internal {
        vm.startPrank(from);
        IERC20(_gnoToken).approve(vault, amount);
        IGnoVault(vault).deposit(amount, to, address(0));
        vm.stopPrank();
    }

    function _collateralizeGnoVault(address vault) internal {
        _collateralizeVault(_keeper, _validatorsRegistry, vault);
    }

    function _setGnoVaultReward(address vault, int160 totalReward, uint160 unlockedMevReward)
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

    function _registerGnoValidator(address vault, uint256 depositAmount, bool isV1Validator)
        internal
        returns (bytes memory publicKey)
    {
        // multiply by 32 to convert GNO to mGNO
        return _registerValidator(_keeper, _validatorsRegistry, vault, depositAmount * 32, isV1Validator);
    }

    function _getGnoValidatorApproval(address vault, uint256 depositAmount, string memory ipfsHash, bool isV1Validator)
        internal
        view
        returns (IKeeperValidators.ApprovalParams memory harvestParams)
    {
        uint256[] memory deposits = new uint256[](1);
        deposits[0] = (depositAmount * 32) / 1 gwei;

        harvestParams = _getValidatorsApproval(_keeper, _validatorsRegistry, vault, ipfsHash, deposits, isV1Validator);
    }

    function _getOrCreateVault(VaultType vaultType, address admin, bytes memory initParams, bool isOwnMevEscrow)
        internal
        returns (address vault)
    {
        vault = _getForkVault(vaultType);
        if (vault != address(0)) {
            _upgradeVault(vaultType, vault);
            if (Keeper(_keeper).isHarvestRequired(vault)) {
                IKeeperRewards.HarvestParams memory harvestParams = _setGnoVaultReward(vault, 0, 0);
                IVaultState(vault).updateState(harvestParams);
            }
        } else {
            vault = _createVault(vaultType, admin, initParams, isOwnMevEscrow);
        }

        address currentAdmin = IGnoVault(vault).admin();
        if (currentAdmin != admin) {
            vm.prank(currentAdmin);
            IGnoVault(vault).setAdmin(admin);
        }
    }

    function _getOrCreateFactory(VaultType _vaultType) internal returns (GnoVaultFactory) {
        if (_vaultFactories[_vaultType] != address(0)) {
            return GnoVaultFactory(_vaultFactories[_vaultType]);
        }

        address impl = _getOrCreateVaultImpl(_vaultType);
        GnoVaultFactory factory = new GnoVaultFactory(impl, IVaultsRegistry(_vaultsRegistry), _gnoToken);

        _vaultFactories[_vaultType] = address(factory);

        vm.prank(VaultsRegistry(_vaultsRegistry).owner());
        VaultsRegistry(_vaultsRegistry).addFactory(address(factory));

        return factory;
    }

    function _getOrCreateMetaFactory(VaultType _vaultType) internal returns (GnoMetaVaultFactory) {
        if (_vaultFactories[_vaultType] != address(0)) {
            return GnoMetaVaultFactory(_vaultFactories[_vaultType]);
        }

        address impl = _getOrCreateVaultImpl(_vaultType);
        GnoMetaVaultFactory factory =
            new GnoMetaVaultFactory(address(this), impl, IVaultsRegistry(_vaultsRegistry), _gnoToken);

        _vaultFactories[_vaultType] = address(factory);

        vm.prank(VaultsRegistry(_vaultsRegistry).owner());
        VaultsRegistry(_vaultsRegistry).addFactory(address(factory));

        return factory;
    }

    function _getPrevVersionVaultFactory(VaultType _vaultType) internal pure returns (GnoVaultFactory) {
        if (_vaultType == VaultType.GnoVault) {
            return GnoVaultFactory(0xC2ecc7620416bd65bfab7010B0db955a0e49579a);
        } else if (_vaultType == VaultType.GnoPrivVault) {
            return GnoVaultFactory(0x574952EC88b2fC271d0C0dB130794c86Ea42139A);
        } else if (_vaultType == VaultType.GnoBlocklistVault) {
            return GnoVaultFactory(0x78FbfBd1DD38892476Ac469325df36604A27F5B7);
        } else if (_vaultType == VaultType.GnoErc20Vault) {
            return GnoVaultFactory(0xF6BBBc05536Ab198d4b7Ab74a93f8e2d4cAd5354);
        } else if (_vaultType == VaultType.GnoPrivErc20Vault) {
            return GnoVaultFactory(0x48319f97E5Da1233c21c48b80097c0FB7a20Ff86);
        }
        return GnoVaultFactory(0x99E4300326867FE3f97864a74e500d19654c19e9);
    }

    function _setGnoWithdrawals(address vault, uint256 amount) internal {
        // Mint GNO to the validators registry
        _mintGnoToken(_validatorsRegistry, amount);

        // Access the system address to execute withdrawals
        address systemAddr = 0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE;
        vm.deal(systemAddr, 1 ether);

        // Calculate the call amount
        uint64 callAmount = uint64((amount * 32) / 1 gwei);

        uint64[] memory amounts = new uint64[](1);
        amounts[0] = callAmount;

        address[] memory addresses = new address[](1);
        addresses[0] = address(vault);

        // Execute system withdrawals as the system account
        vm.startPrank(systemAddr);
        // Call the executor function - this may need to be adjusted based on the registry implementation
        (bool success,) = _validatorsRegistry.call(
            abi.encodeWithSignature("executeSystemWithdrawals(uint64[],address[])", amounts, addresses)
        );
        vm.stopPrank();

        // Ensure the call was successful
        require(success, "Setting GNO withdrawals failed");
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
        if (vaultType == VaultType.GnoGenesisVault) {
            return 0x4b4406Ed8659D03423490D8b62a1639206dA0A7a;
        }

        if (!vm.envBool("TEST_USE_FORK_VAULTS")) return address(0);

        if (vaultType == VaultType.GnoVault) {
            return 0x00025C729A3364FaEf02c7D1F577068d87E90ba6;
        } else if (vaultType == VaultType.GnoBlocklistVault) {
            return 0x79Dbec2d18A758C62D410F9763956D52fbd4A3CC;
        } else if (vaultType == VaultType.GnoPrivVault) {
            return 0x52Bd0fbF4839824680001d3653f2d503C6081085;
        } else if (vaultType == VaultType.GnoErc20Vault) {
            return 0x33C346928eD9249Cf1d5fc16aE32a8CFFa1671AD;
        } else if (vaultType == VaultType.GnoPrivErc20Vault) {
            return 0xdfdA4238359703180DAEc01e48F4625C1569c4dE;
        }
        return address(0);
    }

    function _getVaultRewards(address vault, int160 newTotalReward, uint160 newUnlockedMevReward)
        private
        view
        returns (int160, uint160)
    {
        if (vault == 0x4b4406Ed8659D03423490D8b62a1639206dA0A7a) {
            newTotalReward += 16036446295848871046698;
            newUnlockedMevReward += 16104786197270190915179;
        }

        if (!vm.envBool("TEST_USE_FORK_VAULTS")) {
            return (newTotalReward, newUnlockedMevReward);
        }

        if (vault == 0x00025C729A3364FaEf02c7D1F577068d87E90ba6) {
            newTotalReward += 597138686177531250000;
            newUnlockedMevReward += 2173687084505551299451;
        } else if (vault == 0x79Dbec2d18A758C62D410F9763956D52fbd4A3CC) {
            newTotalReward += 2986604545031250000;
            newUnlockedMevReward += 8209964011439485540;
        } else if (vault == 0x52Bd0fbF4839824680001d3653f2d503C6081085) {
            newTotalReward += 55585164426875000000;
        } else if (vault == 0x33C346928eD9249Cf1d5fc16aE32a8CFFa1671AD) {
            newTotalReward += 118624342091343750000;
            newUnlockedMevReward += 263665552420563946481;
        } else if (vault == 0xdfdA4238359703180DAEc01e48F4625C1569c4dE) {
            newTotalReward += 45747108062500000;
        }
        return (newTotalReward, newUnlockedMevReward);
    }

    function _createVault(VaultType vaultType, address admin, bytes memory initParams, bool isOwnMevEscrow)
        internal
        returns (address)
    {
        address vaultAddress;
        if (vaultType == VaultType.GnoMetaVault) {
            GnoMetaVaultFactory factory = _getOrCreateMetaFactory(vaultType);
            IERC20(_gnoToken).approve(address(factory), _securityDeposit);
            vaultAddress = factory.createVault(admin, initParams);
        } else {
            GnoVaultFactory factory = _getOrCreateFactory(vaultType);
            vm.startPrank(admin);
            IERC20(_gnoToken).approve(address(factory), _securityDeposit);
            vaultAddress = factory.createVault(initParams, isOwnMevEscrow);
            vm.stopPrank();
        }

        return vaultAddress;
    }

    function _createPrevVersionVault(VaultType vaultType, address admin, bytes memory initParams, bool isOwnMevEscrow)
        internal
        returns (address)
    {
        GnoVaultFactory factory = _getPrevVersionVaultFactory(vaultType);

        vm.startPrank(admin);
        IERC20(_gnoToken).approve(address(factory), _securityDeposit);
        address vaultAddress = factory.createVault(initParams, isOwnMevEscrow);
        vm.stopPrank();

        return vaultAddress;
    }

    function _upgradeVault(VaultType vaultType, address vault) internal {
        GnoVault vaultContract = GnoVault(payable(vault));
        uint256 currentVersion = vaultContract.version();
        if (vaultType == VaultType.GnoGenesisVault) {
            if (currentVersion == 4) return;
            require(currentVersion == 3, "Invalid vault version");
        } else {
            if (currentVersion == 3) return;
            require(currentVersion == 2, "Invalid vault version");
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
        IGnoVault.GnoVaultConstructorArgs memory gnoArgs = IGnoVault.GnoVaultConstructorArgs(
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
            _gnoToken,
            _tokensConverterFactory,
            _exitingAssetsClaimDelay
        );
        IGnoErc20Vault.GnoErc20VaultConstructorArgs memory gnoErc20Args = IGnoErc20Vault.GnoErc20VaultConstructorArgs(
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
            _gnoToken,
            _tokensConverterFactory,
            _exitingAssetsClaimDelay
        );

        if (_vaultType == VaultType.GnoVault) {
            impl = address(new GnoVault(gnoArgs));
        } else if (_vaultType == VaultType.GnoBlocklistVault) {
            impl = address(new GnoBlocklistVault(gnoArgs));
        } else if (_vaultType == VaultType.GnoPrivVault) {
            impl = address(new GnoPrivVault(gnoArgs));
        } else if (_vaultType == VaultType.GnoGenesisVault) {
            impl = address(new GnoGenesisVault(gnoArgs, _poolEscrow, _rewardGnoToken));
        } else if (_vaultType == VaultType.GnoErc20Vault) {
            impl = address(new GnoErc20Vault(gnoErc20Args));
        } else if (_vaultType == VaultType.GnoBlocklistErc20Vault) {
            impl = address(new GnoBlocklistErc20Vault(gnoErc20Args));
        } else if (_vaultType == VaultType.GnoPrivErc20Vault) {
            impl = address(new GnoPrivErc20Vault(gnoErc20Args));
        } else if (_vaultType == VaultType.GnoMetaVault) {
            IGnoMetaVault.GnoMetaVaultConstructorArgs memory gnoMetaVaultArgs = IGnoMetaVault
                .GnoMetaVaultConstructorArgs(
                _keeper,
                _vaultsRegistry,
                _osTokenVaultController,
                _osTokenConfig,
                _osTokenVaultEscrow,
                _curatorsRegistry,
                _gnoToken,
                uint64(_exitingAssetsClaimDelay)
            );
            impl = address(new GnoMetaVault(gnoMetaVaultArgs));
        }
        _vaultImplementations[_vaultType] = impl;

        vm.prank(VaultsRegistry(_vaultsRegistry).owner());
        VaultsRegistry(_vaultsRegistry).addVaultImpl(impl);
    }
}
