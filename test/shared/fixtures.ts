import { ethers, upgrades } from 'hardhat'
import { Fixture } from 'ethereum-waffle'
import { BigNumberish, BytesLike, Contract, Wallet } from 'ethers'
import { arrayify } from 'ethers/lib/utils'
import { signTypedData, SignTypedDataVersion } from '@metamask/eth-sig-util'
import EthereumWallet from 'ethereumjs-wallet'
import {
  EthVault,
  EthVaultFactory,
  EthVaultMock,
  EthKeeper,
  Registry,
  Signers,
} from '../../typechain-types'
import { getValidatorsRegistryFactory } from './contracts'
import { REQUIRED_SIGNERS, SIGNERS } from './constants'

export const createValidatorsRegistry = async function (): Promise<Contract> {
  const validatorsRegistryFactory = await getValidatorsRegistryFactory()
  return validatorsRegistryFactory.deploy()
}

export const createRegistry = async function (owner: Wallet): Promise<Registry> {
  const factory = await ethers.getContractFactory('Registry')
  return (await factory.deploy(owner.address)) as Registry
}

export const createSigners = async function (
  owner: Wallet,
  initialSigners: string[],
  initialRequiredSigners: number
): Promise<Signers> {
  const factory = await ethers.getContractFactory('Signers')
  return (await factory.deploy(owner.address, initialSigners, initialRequiredSigners)) as Signers
}

export const createEthKeeper = async function (
  owner: Wallet,
  signers: Signers,
  registry: Registry,
  validatorsRegistry: Contract
): Promise<EthKeeper> {
  const factory = await ethers.getContractFactory('EthKeeper')
  const instance = await upgrades.deployProxy(factory, [owner.address], {
    unsafeAllow: ['delegatecall'],
    constructorArgs: [signers.address, registry.address, validatorsRegistry.address],
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
  signers: Signers
  keeper: EthKeeper
  validatorsRegistry: Contract
  ethVaultFactory: EthVaultFactory

  createVault(
    operator: Wallet,
    maxTotalAssets: BigNumberish,
    validatorsRoot: BytesLike,
    feePercent: BigNumberish,
    name: string,
    symbol: string,
    validatorsIpfsHash: string
  ): Promise<EthVault>

  createVaultMock(
    operator: Wallet,
    maxTotalAssets: BigNumberish,
    validatorsRoot: BytesLike,
    feePercent: BigNumberish,
    name: string,
    symbol: string,
    validatorsIpfsHash: string
  ): Promise<EthVaultMock>

  getSignatures: (typedData: any, count?: number) => Buffer
}

export const ethVaultFixture: Fixture<EthVaultFixture> = async function ([
  dao,
]): Promise<EthVaultFixture> {
  const registry = await createRegistry(dao)
  const validatorsRegistry = await createValidatorsRegistry()

  const sortedSigners = SIGNERS.sort((signer1, signer2) => {
    const signer1Addr = new EthereumWallet(signer1).getAddressString()
    const signer2Addr = new EthereumWallet(signer2).getAddressString()
    return signer1Addr > signer2Addr ? 1 : -1
  })
  const signers = await createSigners(
    dao,
    sortedSigners.map((s) => new EthereumWallet(s).getAddressString()),
    REQUIRED_SIGNERS
  )
  const keeper = await createEthKeeper(dao, signers, registry, validatorsRegistry)
  const ethVaultFactory = await createEthVaultFactory(keeper, registry, validatorsRegistry)
  await registry.connect(dao).addFactory(ethVaultFactory.address)

  const ethVaultMockFactory = await createEthVaultMockFactory(keeper, registry, validatorsRegistry)
  await registry.connect(dao).addFactory(ethVaultMockFactory.address)

  const ethVault = await ethers.getContractFactory('EthVault')
  const ethVaultMock = await ethers.getContractFactory('EthVaultMock')
  return {
    registry,
    signers,
    keeper,
    validatorsRegistry,
    ethVaultFactory,
    createVault: async (
      operator: Wallet,
      maxTotalAssets: BigNumberish,
      validatorsRoot: BytesLike,
      feePercent: BigNumberish,
      name: string,
      symbol: string,
      validatorsIpfsHash: string
    ): Promise<EthVault> => {
      const tx = await ethVaultFactory
        .connect(operator)
        .createVault(maxTotalAssets, validatorsRoot, feePercent, name, symbol, validatorsIpfsHash)
      const receipt = await tx.wait()
      const vaultAddress = receipt.events?.[receipt.events.length - 1].args?.vault as string
      return ethVault.attach(vaultAddress) as EthVault
    },
    createVaultMock: async (
      operator: Wallet,
      maxTotalAssets: BigNumberish,
      validatorsRoot: BytesLike,
      feePercent: BigNumberish,
      name: string,
      symbol: string,
      validatorsIpfsHash: string
    ): Promise<EthVaultMock> => {
      const tx = await ethVaultMockFactory
        .connect(operator)
        .createVault(maxTotalAssets, validatorsRoot, feePercent, name, symbol, validatorsIpfsHash)
      const receipt = await tx.wait()
      const vaultAddress = receipt.events?.[receipt.events.length - 1].args?.vault as string
      return ethVaultMock.attach(vaultAddress) as EthVaultMock
    },
    getSignatures: (typedData: any, count: number = REQUIRED_SIGNERS): Buffer => {
      const signatures: Buffer[] = []
      for (let i = 0; i < count; i++) {
        signatures.push(
          Buffer.from(
            arrayify(
              signTypedData({
                privateKey: sortedSigners[i],
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
