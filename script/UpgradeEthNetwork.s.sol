// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/console.sol';
import {Strings} from '@openzeppelin/contracts/utils/Strings.sol';
import {IEthVault} from '../contracts/interfaces/IEthVault.sol';
import {IEthErc20Vault} from '../contracts/interfaces/IEthErc20Vault.sol';
import {IVaultsRegistry} from '../contracts/interfaces/IVaultsRegistry.sol';
import {IVaultVersion} from '../contracts/interfaces/IVaultVersion.sol';
import {ConsolidationsChecker} from '../contracts/validators/ConsolidationsChecker.sol';
import {EthBlocklistErc20Vault} from '../contracts/vaults/ethereum/EthBlocklistErc20Vault.sol';
import {EthBlocklistVault} from '../contracts/vaults/ethereum/EthBlocklistVault.sol';
import {EthErc20Vault} from '../contracts/vaults/ethereum/EthErc20Vault.sol';
import {EthGenesisVault} from '../contracts/vaults/ethereum/EthGenesisVault.sol';
import {EthPrivErc20Vault} from '../contracts/vaults/ethereum/EthPrivErc20Vault.sol';
import {EthPrivVault} from '../contracts/vaults/ethereum/EthPrivVault.sol';
import {EthVault} from '../contracts/vaults/ethereum/EthVault.sol';
import {EthVaultFactory} from '../contracts/vaults/ethereum/EthVaultFactory.sol';
import {Network} from './Network.sol';

contract UpgradeEthNetwork is Script {
  Network.Constants public constants;
  address public consolidationsChecker;
  address[] public vaultImpls;
  address[] public vaultFactories;

  function run() external {
    vm.startBroadcast(vm.envUint('PRIVATE_KEY'));
    console.log('Deploying from: ', msg.sender);

    constants = Network.getNetworkConstants(block.chainid);

    // Deploy consolidations checker
    consolidationsChecker = address(new ConsolidationsChecker(constants.keeper));

    _deployImplementations();
    _deployFactories();

    vm.stopBroadcast();
  }

  function _deployImplementations() internal {
    // constructors for implementations
    IEthVault.EthVaultConstructorArgs memory vaultArgs = _getEthVaultConstructorArgs();
    IEthErc20Vault.EthErc20VaultConstructorArgs
      memory erc20VaultArgs = _getEthErc20VaultConstructorArgs();

    // deploy genesis vault
    vaultArgs.exitingAssetsClaimDelay = Network.PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY;
    erc20VaultArgs.exitingAssetsClaimDelay = Network.PUBLIC_VAULT_EXITED_ASSETS_CLAIM_DELAY;

    EthGenesisVault ethGenesisVault = new EthGenesisVault(
      vaultArgs,
      constants.legacyPoolEscrow,
      constants.legacyRewardToken
    );

    // deploy normal vaults
    EthVault ethVault = new EthVault(vaultArgs);
    EthErc20Vault ethErc20Vault = new EthErc20Vault(erc20VaultArgs);

    // deploy blocklist vaults
    EthBlocklistVault ethBlocklistVault = new EthBlocklistVault(vaultArgs);
    EthBlocklistErc20Vault ethBlocklistErc20Vault = new EthBlocklistErc20Vault(erc20VaultArgs);

    // deploy private vaults
    // update exited assets claim delay for private vaults
    vaultArgs.exitingAssetsClaimDelay = Network.PRIVATE_VAULT_EXITED_ASSETS_CLAIM_DELAY;
    erc20VaultArgs.exitingAssetsClaimDelay = Network.PRIVATE_VAULT_EXITED_ASSETS_CLAIM_DELAY;
    EthPrivVault ethPrivVault = new EthPrivVault(vaultArgs);
    EthPrivErc20Vault ethPrivErc20Vault = new EthPrivErc20Vault(erc20VaultArgs);

    vaultImpls.push(address(ethGenesisVault));
    vaultImpls.push(address(ethVault));
    vaultImpls.push(address(ethErc20Vault));
    vaultImpls.push(address(ethBlocklistVault));
    vaultImpls.push(address(ethBlocklistErc20Vault));
    vaultImpls.push(address(ethPrivVault));
    vaultImpls.push(address(ethPrivErc20Vault));
  }

  function _deployFactories() internal {
    for (uint256 i = 0; i < vaultImpls.length; i++) {
      address vaultImpl = vaultImpls[i];
      if (IVaultVersion(vaultImpl).vaultId() == keccak256('EthGenesisVault')) {
        continue;
      }
      EthVaultFactory factory = new EthVaultFactory(
        vaultImpl,
        IVaultsRegistry(constants.vaultsRegistry)
      );
      vaultFactories.push(address(factory));
    }
  }

  function _getEthVaultConstructorArgs()
    internal
    view
    returns (IEthVault.EthVaultConstructorArgs memory)
  {
    return
      IEthVault.EthVaultConstructorArgs({
        keeper: constants.keeper,
        vaultsRegistry: constants.vaultsRegistry,
        validatorsRegistry: constants.validatorsRegistry,
        validatorsWithdrawals: constants.validatorsWithdrawals,
        validatorsConsolidations: constants.validatorsConsolidations,
        consolidationsChecker: consolidationsChecker,
        osTokenVaultController: constants.osTokenVaultController,
        osTokenConfig: constants.osTokenConfig,
        osTokenVaultEscrow: constants.osTokenVaultEscrow,
        sharedMevEscrow: constants.sharedMevEscrow,
        depositDataRegistry: constants.depositDataRegistry,
        exitingAssetsClaimDelay: constants.exitedAssetsClaimDelay
      });
  }

  function _getEthErc20VaultConstructorArgs()
    internal
    view
    returns (IEthErc20Vault.EthErc20VaultConstructorArgs memory)
  {
    return
      IEthErc20Vault.EthErc20VaultConstructorArgs({
        keeper: constants.keeper,
        vaultsRegistry: constants.vaultsRegistry,
        validatorsRegistry: constants.validatorsRegistry,
        validatorsWithdrawals: constants.validatorsWithdrawals,
        validatorsConsolidations: constants.validatorsConsolidations,
        consolidationsChecker: consolidationsChecker,
        osTokenVaultController: constants.osTokenVaultController,
        osTokenConfig: constants.osTokenConfig,
        osTokenVaultEscrow: constants.osTokenVaultEscrow,
        sharedMevEscrow: constants.sharedMevEscrow,
        depositDataRegistry: constants.depositDataRegistry,
        exitingAssetsClaimDelay: constants.exitedAssetsClaimDelay
      });
  }

  function _generateGovernorTxJson() internal {
    string[] memory objects = new string[](vaultImpls.length + vaultFactories.length);
    for (uint256 i = 0; i < vaultImpls.length; i++) {
      string memory object = Strings.toString(i);
      vm.serializeAddress(object, 'to', constants.vaultsRegistry);
      vm.serializeString(object, 'operation', '0');
      vm.serializeBytes(
        object,
        'data',
        abi.encodeWithSelector(
          IVaultsRegistry(constants.vaultsRegistry).addVaultImpl.selector,
          vaultImpls[i]
        )
      );
      objects[i] = vm.serializeString(object, 'value', '0.0');
    }

    for (uint256 i = 0; i < vaultFactories.length; i++) {
      string memory object = Strings.toString(vaultImpls.length + i);
      vm.serializeAddress(object, 'to', constants.vaultsRegistry);
      vm.serializeString(object, 'operation', '0');
      vm.serializeBytes(
        object,
        'data',
        abi.encodeWithSelector(
          IVaultsRegistry(constants.vaultsRegistry).addFactory.selector,
          vaultFactories[i]
        )
      );
      objects[vaultImpls.length + i] = vm.serializeString(object, 'value', '0.0');
    }
    string memory json = 'json';
    string memory output = vm.serializeString(json, 'transactions', objects);
    vm.writeJson(output, './output/example.json');
  }
}
