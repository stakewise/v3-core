import { ContractFactory } from 'ethers'
import { ethers } from 'hardhat'
import EthValidatorsRegistry from './artifacts/EthValidatorsRegistry.json'
import EthVaultV1 from './artifacts/EthVault.json'
import EthErc20VaultV1 from './artifacts/EthErc20Vault.json'
import EthPrivErc20VaultV1 from './artifacts/EthPrivErc20Vault.json'
import EthPrivVaultV1 from './artifacts/EthPrivVault.json'
import EthGenesisVaultV1 from './artifacts/EthGenesisVault.json'

export async function getEthValidatorsRegistryFactory(): Promise<ContractFactory> {
  return await ethers.getContractFactory(EthValidatorsRegistry.abi, EthValidatorsRegistry.bytecode)
}

export async function getEthVaultV1Factory(): Promise<ContractFactory> {
  return await ethers.getContractFactory(EthVaultV1.abi, EthVaultV1.bytecode)
}

export async function getEthErc20VaultV1Factory(): Promise<ContractFactory> {
  return await ethers.getContractFactory(EthErc20VaultV1.abi, EthErc20VaultV1.bytecode)
}

export async function getEthPrivErc20VaultV1Factory(): Promise<ContractFactory> {
  return await ethers.getContractFactory(EthPrivErc20VaultV1.abi, EthPrivErc20VaultV1.bytecode)
}

export async function getEthPrivVaultV1Factory(): Promise<ContractFactory> {
  return await ethers.getContractFactory(EthPrivVaultV1.abi, EthPrivVaultV1.bytecode)
}

export async function getEthGenesisVaultV1Factory(): Promise<ContractFactory> {
  return await ethers.getContractFactory(EthGenesisVaultV1.abi, EthGenesisVaultV1.bytecode)
}
