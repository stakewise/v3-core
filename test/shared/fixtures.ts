import { ethers, upgrades } from 'hardhat'
import { Fixture } from 'ethereum-waffle'
import { Contract, Wallet } from 'ethers'
import { arrayify } from 'ethers/lib/utils'
import { signTypedData, SignTypedDataVersion } from '@metamask/eth-sig-util'
import EthereumWallet from 'ethereumjs-wallet'
import {
  EthVault,
  IEthVaultFactory,
  EthVaultFactory,
  EthVaultMock,
  EthKeeper,
  Registry,
  Oracles,
} from '../../typechain-types'
import { getValidatorsRegistryFactory } from './contracts'
import { REQUIRED_ORACLES, ORACLES, ORACLES_CONFIG } from './constants'

export const createValidatorsRegistry = async function (): Promise<Contract> {
  const validatorsRegistryFactory = await getValidatorsRegistryFactory()
  return validatorsRegistryFactory.deploy()
}

export const createRegistry = async function (owner: Wallet): Promise<Registry> {
  const factory = await ethers.getContractFactory('Registry')
  return (await factory.deploy(owner.address)) as Registry
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

export const createEthKeeper = async function (
  owner: Wallet,
  oracles: Oracles,
  registry: Registry,
  validatorsRegistry: Contract
): Promise<EthKeeper> {
  const factory = await ethers.getContractFactory('EthKeeper')
  const instance = await upgrades.deployProxy(factory, [owner.address], {
    unsafeAllow: ['delegatecall'],
    constructorArgs: [oracles.address, registry.address, validatorsRegistry.address],
  })
  return (await instance.deployed()) as EthKeeper
}

export const createEthVaultFactory = async function (
  keeper: EthKeeper,
  registry: Registry,
  validatorsRegistry: Contract
): Promise<EthVaultFactory> {
  const ethVault = await ethers.getContractFactory('EthVault')
  const ethVaultImpl = await upgrades.deployImplementation(ethVault, {
    unsafeAllow: ['delegatecall'],
    constructorArgs: [keeper.address, registry.address, validatorsRegistry.address],
  })

  const factory = await ethers.getContractFactory('EthVaultFactory')
  return (await factory.deploy(ethVaultImpl, registry.address)) as EthVaultFactory
}

export const createEthVaultMockFactory = async function (
  keeper: EthKeeper,
  registry: Registry,
  validatorsRegistry: Contract
): Promise<EthVaultFactory> {
  const ethVaultMock = await ethers.getContractFactory('EthVaultMock')
  const ethVaultMockImpl = await upgrades.deployImplementation(ethVaultMock, {
    unsafeAllow: ['delegatecall'],
    constructorArgs: [keeper.address, registry.address, validatorsRegistry.address],
  })

  const factory = await ethers.getContractFactory('EthVaultFactory')
  return (await factory.deploy(ethVaultMockImpl, registry.address)) as EthVaultFactory
}

interface EthVaultFixture {
  registry: Registry
  oracles: Oracles
  keeper: EthKeeper
  validatorsRegistry: Contract
  ethVaultFactory: EthVaultFactory
  getSignatures: (typedData: any, count?: number) => Buffer

  createVault(admin: Wallet, vaultParams: IEthVaultFactory.VaultParamsStruct): Promise<EthVault>

  createVaultMock(
    admin: Wallet,
    vaultParams: IEthVaultFactory.VaultParamsStruct
  ): Promise<EthVaultMock>
}

export const ethVaultFixture: Fixture<EthVaultFixture> = async function ([
  dao,
]): Promise<EthVaultFixture> {
  const registry = await createRegistry(dao)
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
  const keeper = await createEthKeeper(dao, oracles, registry, validatorsRegistry)
  const ethVaultFactory = await createEthVaultFactory(keeper, registry, validatorsRegistry)
  await registry.connect(dao).addFactory(ethVaultFactory.address)

  const ethVaultMockFactory = await createEthVaultMockFactory(keeper, registry, validatorsRegistry)
  await registry.connect(dao).addFactory(ethVaultMockFactory.address)

  const ethVault = await ethers.getContractFactory('EthVault')
  const ethVaultMock = await ethers.getContractFactory('EthVaultMock')
  return {
    registry,
    oracles,
    keeper,
    validatorsRegistry,
    ethVaultFactory,
    createVault: async (
      admin: Wallet,
      vaultParams: IEthVaultFactory.VaultParamsStruct
    ): Promise<EthVault> => {
      const tx = await ethVaultFactory.connect(admin).createVault(vaultParams)
      const receipt = await tx.wait()
      const vaultAddress = receipt.events?.[receipt.events.length - 1].args?.vault as string
      return ethVault.attach(vaultAddress) as EthVault
    },
    createVaultMock: async (
      admin: Wallet,
      vaultParams: IEthVaultFactory.VaultParamsStruct
    ): Promise<EthVaultMock> => {
      const tx = await ethVaultMockFactory.connect(admin).createVault(vaultParams)
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
