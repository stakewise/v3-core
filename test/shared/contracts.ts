import { Contract, ContractFactory } from 'ethers'
import { ethers } from 'hardhat'
import EthValidatorsRegistry from './artifacts/EthValidatorsRegistry.json'
import GnoValidatorsRegistry from './artifacts/GnoValidatorsRegistry.json'
import EthVaultV1 from './artifacts/EthVaultV1.json'
import EthVault from './artifacts/EthVault.json'
import EthErc20Vault from './artifacts/EthErc20Vault.json'
import EthPrivErc20Vault from './artifacts/EthPrivErc20Vault.json'
import EthPrivVault from './artifacts/EthPrivVault.json'
import EthBlocklistVault from './artifacts/EthBlocklistVault.json'
import EthBlocklistErc20Vault from './artifacts/EthBlocklistErc20Vault.json'
import GnoVault from './artifacts/GnoVault.json'
import GnoPrivVault from './artifacts/GnoPrivVault.json'
import GnoErc20Vault from './artifacts/GnoErc20Vault.json'
import GnoPrivErc20Vault from './artifacts/GnoPrivErc20Vault.json'
import GnoBlocklistVault from './artifacts/GnoBlocklistVault.json'
import GnoBlocklistErc20Vault from './artifacts/GnoBlocklistErc20Vault.json'
import GnoGenesisVault from './artifacts/GnoGenesisVault.json'
import EthGenesisVault from './artifacts/EthGenesisVault.json'
import EigenPodManager from './artifacts/EigenPodManager.json'
import EigenDelegationManager from './artifacts/EigenDelegationManager.json'
import EigenDelayedWithdrawalRouter from './artifacts/EigenDelayedWithdrawalRouter.json'
import { MAINNET_FORK } from '../../helpers/constants'

export async function getEthValidatorsRegistryFactory(): Promise<ContractFactory> {
  return await ethers.getContractFactory(EthValidatorsRegistry.abi, EthValidatorsRegistry.bytecode)
}

export async function getGnoValidatorsRegistryFactory(): Promise<ContractFactory> {
  return await ethers.getContractFactory(GnoValidatorsRegistry.abi, GnoValidatorsRegistry.bytecode)
}

export async function getEthVaultV1Factory(): Promise<ContractFactory> {
  return await ethers.getContractFactory(EthVaultV1.abi, EthVaultV1.bytecode)
}

export async function getEthVaultV3Factory(): Promise<ContractFactory> {
  return await ethers.getContractFactory(EthVault.abi, EthVault.bytecode)
}

export async function getEthErc20VaultV3Factory(): Promise<ContractFactory> {
  return await ethers.getContractFactory(EthErc20Vault.abi, EthErc20Vault.bytecode)
}

export async function getEthPrivErc20VaultV3Factory(): Promise<ContractFactory> {
  return await ethers.getContractFactory(EthPrivErc20Vault.abi, EthPrivErc20Vault.bytecode)
}

export async function getEthBlocklistErc20VaultV3Factory(): Promise<ContractFactory> {
  return await ethers.getContractFactory(
    EthBlocklistErc20Vault.abi,
    EthBlocklistErc20Vault.bytecode
  )
}

export async function getEthPrivVaultV3Factory(): Promise<ContractFactory> {
  return await ethers.getContractFactory(EthPrivVault.abi, EthPrivVault.bytecode)
}

export async function getEthBlocklistVaultV3Factory(): Promise<ContractFactory> {
  return await ethers.getContractFactory(EthBlocklistVault.abi, EthBlocklistVault.bytecode)
}

export async function getEthGenesisVaultV3Factory(): Promise<ContractFactory> {
  return await ethers.getContractFactory(EthGenesisVault.abi, EthGenesisVault.bytecode)
}

export async function getGnoVaultV2Factory(): Promise<ContractFactory> {
  return await ethers.getContractFactory(GnoVault.abi, GnoVault.bytecode)
}

export async function getGnoPrivVaultV2Factory(): Promise<ContractFactory> {
  return await ethers.getContractFactory(GnoPrivVault.abi, GnoPrivVault.bytecode)
}

export async function getGnoErc20VaultV2Factory(): Promise<ContractFactory> {
  return await ethers.getContractFactory(GnoErc20Vault.abi, GnoErc20Vault.bytecode)
}

export async function getGnoPrivErc20VaultV2Factory(): Promise<ContractFactory> {
  return await ethers.getContractFactory(GnoPrivErc20Vault.abi, GnoPrivErc20Vault.bytecode)
}

export async function getGnoBlocklistVaultV2Factory(): Promise<ContractFactory> {
  return await ethers.getContractFactory(GnoBlocklistVault.abi, GnoBlocklistVault.bytecode)
}

export async function getGnoBlocklistErc20VaultV2Factory(): Promise<ContractFactory> {
  return await ethers.getContractFactory(
    GnoBlocklistErc20Vault.abi,
    GnoBlocklistErc20Vault.bytecode
  )
}

export async function getGnoGenesisVaultV2Factory(): Promise<ContractFactory> {
  return await ethers.getContractFactory(GnoGenesisVault.abi, GnoGenesisVault.bytecode)
}

export async function getEigenPodManager(): Promise<Contract> {
  return await ethers.getContractAt(EigenPodManager.abi, MAINNET_FORK.eigenPodManager)
}

export async function getEigenDelegationManager(): Promise<Contract> {
  return await ethers.getContractAt(EigenDelegationManager.abi, MAINNET_FORK.eigenDelegationManager)
}

export async function getEigenDelayedWithdrawalRouter(): Promise<Contract> {
  return await ethers.getContractAt(
    EigenDelayedWithdrawalRouter.abi,
    MAINNET_FORK.eigenDelayedWithdrawalRouter
  )
}
