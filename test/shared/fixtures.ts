import { ethers, upgrades } from 'hardhat'
import { Fixture } from 'ethereum-waffle'
import { Contract, Wallet } from 'ethers'
import { arrayify } from 'ethers/lib/utils'
import { signTypedData, SignTypedDataVersion } from '@metamask/eth-sig-util'
import EthereumWallet from 'ethereumjs-wallet'
import {
  EthVault,
  EthPrivateVault,
  IEthVaultFactory,
  EthVaultFactory,
  EthVaultMock,
  VaultsRegistry,
  Oracles,
  Keeper,
} from '../../typechain-types'
import { getValidatorsRegistryFactory } from './contracts'
import { REQUIRED_ORACLES, ORACLES, ORACLES_CONFIG } from './constants'

export const createValidatorsRegistry = async function (): Promise<Contract> {
  const validatorsRegistryFactory = await getValidatorsRegistryFactory()
  return validatorsRegistryFactory.deploy()
}

export const createVaultsRegistry = async function (owner: Wallet): Promise<VaultsRegistry> {
  const factory = await ethers.getContractFactory('VaultsRegistry')
  return (await factory.deploy(owner.address)) as VaultsRegistry
}

export const createOracles = async function (
  owner: Wallet,
  initialOracles: string[],
  initialRequiredOracles: number,
  configIpfsHash: string
): Promise<Oracles> {
  const factory = await ethers.getContractFactory('Oracles')
  return (await factory.deploy(
    owner.address,
    initialOracles,
    initialRequiredOracles,
    configIpfsHash
  )) as Oracles
}

export const createKeeper = async function (
  owner: Wallet,
  oracles: Oracles,
  vaultsRegistry: VaultsRegistry,
  validatorsRegistry: Contract
): Promise<Keeper> {
  const factory = await ethers.getContractFactory('Keeper')
  const instance = await upgrades.deployProxy(factory, [owner.address], {
    unsafeAllow: ['delegatecall'],
    constructorArgs: [oracles.address, vaultsRegistry.address, validatorsRegistry.address],
  })
  return (await instance.deployed()) as Keeper
}

export const createEthVaultFactory = async function (
  keeper: Keeper,
  vaultsRegistry: VaultsRegistry,
  validatorsRegistry: Contract
): Promise<EthVaultFactory> {
  const ethVault = await ethers.getContractFactory('EthVault')
  const ethVaultImpl = await upgrades.deployImplementation(ethVault, {
    unsafeAllow: ['delegatecall'],
    constructorArgs: [keeper.address, vaultsRegistry.address, validatorsRegistry.address],
  })

  const ethPrivateVault = await ethers.getContractFactory('EthPrivateVault')
  const ethPrivateVaultImpl = await upgrades.deployImplementation(ethPrivateVault, {
    unsafeAllow: ['delegatecall'],
    constructorArgs: [keeper.address, vaultsRegistry.address, validatorsRegistry.address],
  })

  const factory = await ethers.getContractFactory('EthVaultFactory')
  return (await factory.deploy(
    ethVaultImpl,
    ethPrivateVaultImpl,
    vaultsRegistry.address
  )) as EthVaultFactory
}

export const createEthVaultMockFactory = async function (
  keeper: Keeper,
  vaultsRegistry: VaultsRegistry,
  validatorsRegistry: Contract
): Promise<EthVaultFactory> {
  const ethVaultMock = await ethers.getContractFactory('EthVaultMock')
  const ethVaultMockImpl = await upgrades.deployImplementation(ethVaultMock, {
    unsafeAllow: ['delegatecall'],
    constructorArgs: [keeper.address, vaultsRegistry.address, validatorsRegistry.address],
  })

  const ethPrivateVault = await ethers.getContractFactory('EthPrivateVault')
  const ethPrivateVaultImpl = await upgrades.deployImplementation(ethPrivateVault, {
    unsafeAllow: ['delegatecall'],
    constructorArgs: [keeper.address, vaultsRegistry.address, validatorsRegistry.address],
  })

  const factory = await ethers.getContractFactory('EthVaultFactory')
  return (await factory.deploy(
    ethVaultMockImpl,
    ethPrivateVaultImpl,
    vaultsRegistry.address
  )) as EthVaultFactory
}

interface EthVaultFixture {
  vaultsRegistry: VaultsRegistry
  oracles: Oracles
  keeper: Keeper
  validatorsRegistry: Contract
  ethVaultFactory: EthVaultFactory
  getSignatures: (typedData: any, count?: number) => Buffer

  createVault(admin: Wallet, vaultParams: IEthVaultFactory.VaultParamsStruct): Promise<EthVault>

  createPrivateVault(
    admin: Wallet,
    vaultParams: IEthVaultFactory.VaultParamsStruct
  ): Promise<EthPrivateVault>

  createVaultMock(
    admin: Wallet,
    vaultParams: IEthVaultFactory.VaultParamsStruct
  ): Promise<EthVaultMock>
}

export const ethVaultFixture: Fixture<EthVaultFixture> = async function ([
  dao,
]): Promise<EthVaultFixture> {
  const registry = await createVaultsRegistry(dao)
  const validatorsRegistry = await createValidatorsRegistry()

  const sortedOracles = ORACLES.sort((oracle1, oracle2) => {
    const oracle1Addr = new EthereumWallet(oracle1).getAddressString()
    const oracle2Addr = new EthereumWallet(oracle2).getAddressString()
    return oracle1Addr > oracle2Addr ? 1 : -1
  })
  const oracles = await createOracles(
    dao,
    sortedOracles.map((s) => new EthereumWallet(s).getAddressString()),
    REQUIRED_ORACLES,
    ORACLES_CONFIG
  )
  const keeper = await createKeeper(dao, oracles, registry, validatorsRegistry)
  const ethVaultFactory = await createEthVaultFactory(keeper, registry, validatorsRegistry)
  await registry.connect(dao).addFactory(ethVaultFactory.address)

  const ethVaultMockFactory = await createEthVaultMockFactory(keeper, registry, validatorsRegistry)
  await registry.connect(dao).addFactory(ethVaultMockFactory.address)

  const ethVault = await ethers.getContractFactory('EthVault')
  const ethPrivateVault = await ethers.getContractFactory('EthPrivateVault')
  const ethVaultMock = await ethers.getContractFactory('EthVaultMock')
  return {
    vaultsRegistry: registry,
    oracles,
    keeper,
    validatorsRegistry,
    ethVaultFactory,
    createVault: async (
      admin: Wallet,
      vaultParams: IEthVaultFactory.VaultParamsStruct
    ): Promise<EthVault> => {
      const tx = await ethVaultFactory.connect(admin).createVault(vaultParams, false)
      const receipt = await tx.wait()
      const vaultAddress = receipt.events?.[receipt.events.length - 1].args?.vault as string
      return ethVault.attach(vaultAddress) as EthVault
    },
    createPrivateVault: async (
      admin: Wallet,
      vaultParams: IEthVaultFactory.VaultParamsStruct
    ): Promise<EthPrivateVault> => {
      const tx = await ethVaultFactory.connect(admin).createVault(vaultParams, true)
      const receipt = await tx.wait()
      const vaultAddress = receipt.events?.[receipt.events.length - 1].args?.vault as string
      return ethPrivateVault.attach(vaultAddress) as EthPrivateVault
    },
    createVaultMock: async (
      admin: Wallet,
      vaultParams: IEthVaultFactory.VaultParamsStruct
    ): Promise<EthVaultMock> => {
      const tx = await ethVaultMockFactory.connect(admin).createVault(vaultParams, false)
      const receipt = await tx.wait()
      const vaultAddress = receipt.events?.[receipt.events.length - 1].args?.vault as string
      return ethVaultMock.attach(vaultAddress) as EthVaultMock
    },
    getSignatures: (typedData: any, count: number = REQUIRED_ORACLES): Buffer => {
      const signatures: Buffer[] = []
      for (let i = 0; i < count; i++) {
        signatures.push(
          Buffer.from(
            arrayify(
              signTypedData({
                privateKey: sortedOracles[i],
                data: typedData,
                version: SignTypedDataVersion.V4,
              })
            )
          )
        )
      }
      return Buffer.concat(signatures)
    },
  }
}
