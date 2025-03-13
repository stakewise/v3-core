// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IKeeperValidators} from '../../contracts/interfaces/IKeeperValidators.sol';
import {IOsTokenConfig} from '../../contracts/interfaces/IOsTokenConfig.sol';
import {IOsTokenVaultController} from '../../contracts/interfaces/IOsTokenVaultController.sol';
import {IOsTokenVaultEscrow} from '../../contracts/interfaces/IOsTokenVaultEscrow.sol';
import {ISharedMevEscrow} from '../../contracts/interfaces/ISharedMevEscrow.sol';
import {IValidatorsRegistry} from '../../contracts/interfaces/IValidatorsRegistry.sol';
import {IMerkleDistributor} from '../../contracts/interfaces/IMerkleDistributor.sol';
import {GnoDaiDistributor} from '../../contracts/misc/GnoDaiDistributor.sol';
import {ConsolidationsChecker} from '../../contracts/validators/ConsolidationsChecker.sol';
import {GnoBlocklistErc20Vault} from '../../contracts/vaults/gnosis/GnoBlocklistErc20Vault.sol';
import {GnoBlocklistVault} from '../../contracts/vaults/gnosis/GnoBlocklistVault.sol';
import {GnoErc20Vault} from '../../contracts/vaults/gnosis/GnoErc20Vault.sol';
import {GnoGenesisVault} from '../../contracts/vaults/gnosis/GnoGenesisVault.sol';
import {GnoPrivErc20Vault} from '../../contracts/vaults/gnosis/GnoPrivErc20Vault.sol';
import {GnoPrivVault} from '../../contracts/vaults/gnosis/GnoPrivVault.sol';
import {GnoVault, IGnoVault} from '../../contracts/vaults/gnosis/GnoVault.sol';
import {GnoVaultFactory} from '../../contracts/vaults/gnosis/GnoVaultFactory.sol';
import {Keeper} from '../../contracts/keeper/Keeper.sol';
import {ValidatorsConsolidationsMock} from '../../contracts/mocks/ValidatorsConsolidationsMock.sol';
import {ValidatorsHelpers} from './ValidatorsHelpers.sol';
import {ValidatorsWithdrawalsMock} from '../../contracts/mocks/ValidatorsWithdrawalsMock.sol';
import {VaultsRegistry, IVaultsRegistry} from '../../contracts/vaults/VaultsRegistry.sol';

interface IGnoToken {
  function mint(address _to, uint256 _amount) external returns (bool);
  function owner() external view returns (address);
}

abstract contract GnoHelpers is Test, ValidatorsHelpers {
  uint256 internal constant forkBlockNumber = 39014183;
  uint256 private constant _securityDeposit = 1e9;
  address private constant _keeper = 0xcAC0e3E35d3BA271cd2aaBE688ac9DB1898C26aa;
  address private constant _validatorsRegistry = 0x0B98057eA310F4d31F2a452B414647007d1645d9;
  address private constant _vaultsRegistry = 0x7d014B3C6ee446563d4e0cB6fBD8C3D0419867cB;
  address private constant _osTokenVaultController = 0x60B2053d7f2a0bBa70fe6CDd88FB47b579B9179a;
  address private constant _osTokenConfig = 0xd6672fbE1D28877db598DC0ac2559A15745FC3ec;
  address private constant _osTokenVaultEscrow = 0x28F325dD287a5984B754d34CfCA38af3A8429e71;
  address private constant _sharedMevEscrow = 0x30db0d10d3774e78f8cB214b9e8B72D4B402488a;
  address private constant _gnoToken = 0x9C58BAcC331c9aa871AFD802DB6379a98e80CEdb;
  address private constant _poolEscrow = 0xfc9B67b6034F6B306EA9Bd8Ec1baf3eFA2490394;
  address private constant _rewardGnoToken = 0x6aC78efae880282396a335CA2F79863A1e6831D4;
  address private constant _merkleDistributor = 0xFBceefdBB0ca25a4043b35EF49C2810425243710;
  address private constant _savingsXDaiAdapter = 0xD499b51fcFc66bd31248ef4b28d656d67E591A94;
  address private constant _sDaiToken = 0xaf204776c7245bF4147c2612BF6e5972Ee483701;
  uint256 private constant _exitingAssetsClaimDelay = 1 days;

  enum VaultType {
    GnoVault,
    GnoBlocklistVault,
    GnoPrivVault,
    GnoGenesisVault,
    GnoErc20Vault,
    GnoBlocklistErc20Vault,
    GnoPrivErc20Vault
  }

  struct ForkContracts {
    Keeper keeper;
    IValidatorsRegistry validatorsRegistry;
    VaultsRegistry vaultsRegistry;
    IOsTokenVaultController osTokenVaultController;
    IOsTokenConfig osTokenConfig;
    IOsTokenVaultEscrow osTokenVaultEscrow;
    ISharedMevEscrow sharedMevEscrow;
    IERC20 gnoToken;
  }

  mapping(VaultType vaultType => address vaultImpl) private _vaultImplementations;
  mapping(VaultType vaultType => address vaultFactory) private _vaultFactories;

  address internal _gnoDaiDistributor;
  address internal _consolidationsChecker;
  address internal _validatorsWithdrawals;
  address internal _validatorsConsolidations;

  function _activateGnosisFork() internal returns (ForkContracts memory) {
    vm.createSelectFork(vm.envString('GNOSIS_RPC_URL'), forkBlockNumber);

    _gnoDaiDistributor = address(
      new GnoDaiDistributor(_sDaiToken, _vaultsRegistry, _savingsXDaiAdapter, _merkleDistributor)
    );
    _validatorsWithdrawals = address(new ValidatorsWithdrawalsMock());
    _validatorsConsolidations = address(new ValidatorsConsolidationsMock());
    _consolidationsChecker = address(new ConsolidationsChecker(address(_keeper)));

    vm.prank(IMerkleDistributor(_merkleDistributor).owner());
    IMerkleDistributor(_merkleDistributor).setDistributor(_gnoDaiDistributor, true);
    return
      ForkContracts({
        keeper: Keeper(_keeper),
        validatorsRegistry: IValidatorsRegistry(_validatorsRegistry),
        vaultsRegistry: VaultsRegistry(_vaultsRegistry),
        osTokenVaultController: IOsTokenVaultController(_osTokenVaultController),
        osTokenConfig: IOsTokenConfig(_osTokenConfig),
        osTokenVaultEscrow: IOsTokenVaultEscrow(_osTokenVaultEscrow),
        sharedMevEscrow: ISharedMevEscrow(_sharedMevEscrow),
        gnoToken: IERC20(_gnoToken)
      });
  }

  function _mintGnoToken(address _to, uint256 _amount) internal {
    vm.prank(IGnoToken(_gnoToken).owner());
    IGnoToken(_gnoToken).mint(_to, _amount);
  }

  function _depositToVault(
    address vault,
    uint256 amount,
    address from,
    address to,
    address referrer
  ) internal {
    vm.startPrank(from);
    IERC20(_gnoToken).approve(vault, amount);
    IGnoVault(vault).deposit(amount, to, referrer);
    vm.stopPrank();
  }

  function _collateralizeVault(address _vault) internal {
    if (Keeper(_keeper).isCollateralized(_vault)) return;

    uint256 validatorsMinOraclesBefore = Keeper(_keeper).validatorsMinOracles();

    // setup oracle
    (address oracle, uint256 oraclePrivateKey) = makeAddrAndKey('oracle');
    address keeperOwner = Keeper(_keeper).owner();
    vm.startPrank(keeperOwner);
    Keeper(_keeper).setValidatorsMinOracles(1);
    Keeper(_keeper).addOracle(oracle);
    vm.stopPrank();

    uint256[] memory depositAmounts = new uint256[](1);
    depositAmounts[0] = 1 ether;
    bytes1[] memory withdrawalCredsPrefixes = new bytes1[](1);
    withdrawalCredsPrefixes[0] = 0x01;
    IKeeperValidators.ApprovalParams memory approvalParams = _getValidatorsApproval(
      oraclePrivateKey,
      _keeper,
      _validatorsRegistry,
      _vault,
      'ipfsHash',
      depositAmounts,
      withdrawalCredsPrefixes
    );

    vm.prank(_vault);
    Keeper(_keeper).approveValidators(approvalParams);

    // revert previous state
    vm.startPrank(keeperOwner);
    Keeper(_keeper).setValidatorsMinOracles(validatorsMinOraclesBefore);
    Keeper(_keeper).removeOracle(oracle);
    vm.stopPrank();
  }

  function _setGnoVaultReward(
    address vault,
    int160 totalReward,
    uint160 unlockedMevReward
  ) internal returns (IKeeperRewards.HarvestParams memory harvestParams) {
    return _setVaultReward(_keeper, _osTokenVaultController, vault, totalReward, unlockedMevReward);
  }

  function _getVaultRewards(
    VaultType vaultType,
    int160 newTotalReward,
    uint160 newUnlockedMevReward
  ) internal view returns (int160, uint160) {
    if (!vm.envBool('GNOSIS_USE_FORK_VAULTS')) {
      return (newTotalReward, newUnlockedMevReward);
    }

    if (vaultType == VaultType.GnoVault) {
      newTotalReward += 393962803328781250000;
      newUnlockedMevReward += 1680633820544574435947;
    } else if (vaultType == VaultType.GnoBlocklistVault) {
      newTotalReward += 1050592958531250000;
      newUnlockedMevReward += 3442955231281615690;
    } else if (vaultType == VaultType.GnoPrivVault) {
      newTotalReward += 32023359208750000000;
    } else if (vaultType == VaultType.GnoGenesisVault) {
      newTotalReward += 14465786742141121046698;
      newUnlockedMevReward += 12291679027502580216003;
    } else if (vaultType == VaultType.GnoErc20Vault) {
      newTotalReward += 93551557523312500000;
      newUnlockedMevReward += 199880304782632057829;
    } else if (vaultType == VaultType.GnoPrivErc20Vault) {
      newTotalReward += 5690635875000000;
    }
    return (newTotalReward, newUnlockedMevReward);
  }

  function _getOrCreateVault(
    VaultType vaultType,
    address admin,
    bytes memory initParams,
    bool isOwnMevEscrow
  ) internal returns (address vault) {
    vault = _getForkVault(vaultType);
    if (vault != address(0)) {
      _upgradeVault(vaultType, vault);
    } else {
      vault = _createVault(vaultType, admin, initParams, isOwnMevEscrow);
    }

    address currentAdmin = IGnoVault(vault).admin();
    if (currentAdmin != admin) {
      vm.prank(currentAdmin);
      IGnoVault(vault).setAdmin(admin);
    }
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
    (bool success, ) = _validatorsRegistry.call(
      abi.encodeWithSignature('executeSystemWithdrawals(uint64[],address[])', amounts, addresses)
    );
    vm.stopPrank();

    // Ensure the call was successful
    require(success, 'Setting GNO withdrawals failed');
  }

  function _startSnapshotGas(string memory label) internal {
    if (vm.envBool('GNOSIS_USE_FORK_VAULTS')) return;
    return vm.startSnapshotGas(label);
  }

  function _stopSnapshotGas() internal {
    if (vm.envBool('GNOSIS_USE_FORK_VAULTS')) return;
    vm.stopSnapshotGas();
  }

  function _getForkVault(VaultType vaultType) private view returns (address) {
    if (!vm.envBool('GNOSIS_USE_FORK_VAULTS')) return address(0);

    if (vaultType == VaultType.GnoVault) {
      return 0x00025C729A3364FaEf02c7D1F577068d87E90ba6;
    } else if (vaultType == VaultType.GnoBlocklistVault) {
      return 0x79Dbec2d18A758C62D410F9763956D52fbd4A3CC;
    } else if (vaultType == VaultType.GnoPrivVault) {
      return 0x52Bd0fbF4839824680001d3653f2d503C6081085;
    } else if (vaultType == VaultType.GnoGenesisVault) {
      return 0x4b4406Ed8659D03423490D8b62a1639206dA0A7a;
    } else if (vaultType == VaultType.GnoErc20Vault) {
      return 0x33C346928eD9249Cf1d5fc16aE32a8CFFa1671AD;
    } else if (vaultType == VaultType.GnoPrivErc20Vault) {
      return 0xdfdA4238359703180DAEc01e48F4625C1569c4dE;
    }
    return address(0);
  }

  function _createVault(
    VaultType vaultType,
    address admin,
    bytes memory initParams,
    bool isOwnMevEscrow
  ) private returns (address) {
    GnoVaultFactory factory = _getOrCreateFactory(vaultType);

    vm.startPrank(admin);
    IERC20(_gnoToken).approve(address(factory), _securityDeposit);
    address vaultAddress = factory.createVault(initParams, isOwnMevEscrow);
    vm.stopPrank();

    return vaultAddress;
  }

  function _getOrCreateFactory(VaultType _vaultType) internal returns (GnoVaultFactory) {
    if (_vaultFactories[_vaultType] != address(0)) {
      return GnoVaultFactory(_vaultFactories[_vaultType]);
    }

    address impl = _getOrCreateVaultImpl(_vaultType);
    GnoVaultFactory factory = new GnoVaultFactory(
      impl,
      IVaultsRegistry(_vaultsRegistry),
      _gnoToken
    );

    _vaultFactories[_vaultType] = address(factory);

    vm.prank(VaultsRegistry(_vaultsRegistry).owner());
    VaultsRegistry(_vaultsRegistry).addFactory(address(factory));

    return factory;
  }

  function _upgradeVault(VaultType vaultType, address vault) private {
    GnoVault vaultContract = GnoVault(payable(vault));
    uint256 currentVersion = vaultContract.version();
    if (vaultType == VaultType.GnoGenesisVault) {
      if (currentVersion == 4) return;
      require(currentVersion == 3, 'Invalid vault version');
    } else {
      if (currentVersion == 3) return;
      require(currentVersion == 2, 'Invalid vault version');
    }
    address newImpl = _getOrCreateVaultImpl(vaultType);
    address admin = vaultContract.admin();

    vm.deal(admin, admin.balance + 1 ether);
    vm.prank(admin);
    vaultContract.upgradeToAndCall(newImpl, '0x');
  }

  function _getOrCreateVaultImpl(VaultType _vaultType) private returns (address impl) {
    if (_vaultImplementations[_vaultType] != address(0)) {
      return _vaultImplementations[_vaultType];
    }

    if (_vaultType == VaultType.GnoVault) {
      impl = address(
        new GnoVault(
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
          _gnoToken,
          _gnoDaiDistributor,
          _exitingAssetsClaimDelay
        )
      );
    } else if (_vaultType == VaultType.GnoBlocklistVault) {
      impl = address(
        new GnoBlocklistVault(
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
          _gnoToken,
          _gnoDaiDistributor,
          _exitingAssetsClaimDelay
        )
      );
    } else if (_vaultType == VaultType.GnoPrivVault) {
      impl = address(
        new GnoPrivVault(
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
          _gnoToken,
          _gnoDaiDistributor,
          _exitingAssetsClaimDelay
        )
      );
    } else if (_vaultType == VaultType.GnoGenesisVault) {
      impl = address(
        new GnoGenesisVault(
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
          _gnoToken,
          _gnoDaiDistributor,
          _poolEscrow,
          _rewardGnoToken,
          _exitingAssetsClaimDelay
        )
      );
    } else if (_vaultType == VaultType.GnoErc20Vault) {
      impl = address(
        new GnoErc20Vault(
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
          _gnoToken,
          _gnoDaiDistributor,
          _exitingAssetsClaimDelay
        )
      );
    } else if (_vaultType == VaultType.GnoBlocklistErc20Vault) {
      impl = address(
        new GnoBlocklistErc20Vault(
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
          _gnoToken,
          _gnoDaiDistributor,
          _exitingAssetsClaimDelay
        )
      );
    } else if (_vaultType == VaultType.GnoPrivErc20Vault) {
      impl = address(
        new GnoPrivErc20Vault(
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
          _gnoToken,
          _gnoDaiDistributor,
          _exitingAssetsClaimDelay
        )
      );
    }
    _vaultImplementations[_vaultType] = impl;

    vm.prank(VaultsRegistry(_vaultsRegistry).owner());
    VaultsRegistry(_vaultsRegistry).addVaultImpl(impl);
  }
}
