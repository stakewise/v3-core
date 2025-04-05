// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IEthVault} from '../contracts/interfaces/IEthVault.sol';
import {IOsTokenConfig} from '../contracts/interfaces/IOsTokenConfig.sol';
import {IKeeperRewards} from '../contracts/interfaces/IKeeperRewards.sol';
import {IOsTokenVaultController} from '../contracts/interfaces/IOsTokenVaultController.sol';
import {Errors} from '../contracts/libraries/Errors.sol';
import {EthHelpers} from './helpers/EthHelpers.sol';

interface IStrategiesRegistry {
  function addStrategyProxy(bytes32 strategyProxyId, address proxy) external;
  function setStrategy(address strategy, bool enabled) external;

  function owner() external view returns (address);
}

contract EthOsTokenVaultEscrowTest is Test, EthHelpers {
  IStrategiesRegistry private constant _strategiesRegistry =
    IStrategiesRegistry(0x90b82E4b3aa385B4A02B7EBc1892a4BeD6B5c465);

  ForkContracts public contracts;
  IEthVault public vault;

  address public user;
  address public admin;

  function setUp() public {
    // Activate Ethereum fork and get contracts
    contracts = _activateEthereumFork();

    // Setup addresses
    user = makeAddr('user');
    admin = makeAddr('admin');

    // Fund accounts
    vm.deal(user, 100 ether);
    vm.deal(admin, 100 ether);

    // Register user
    vm.prank(_strategiesRegistry.owner());
    _strategiesRegistry.setStrategy(address(this), true);
    _strategiesRegistry.addStrategyProxy(keccak256(abi.encode(user)), user);

    // Create a vault
    bytes memory initParams = abi.encode(
      IEthVault.EthVaultInitParams({
        capacity: 1000 ether,
        feePercent: 1000,
        metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
      })
    );
    address _vault = _getOrCreateVault(VaultType.EthVault, admin, initParams, false);
    vault = IEthVault(_vault);
  }
}
