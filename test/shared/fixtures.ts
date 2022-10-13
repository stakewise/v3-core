import { ethers, upgrades } from 'hardhat'
import { Fixture } from 'ethereum-waffle'
import { BigNumberish, Contract } from 'ethers'
import { EthVault, EthVaultFactory, EthVaultMock, Registry } from '../../typechain-types'
import { getValidatorsRegistryFactory } from './contracts'

interface EthVaultFixture {
  validatorsRegistry: Contract
  vaultFactory: EthVaultFactory
  vaultFactoryMock: EthVaultFactory
  registry: Registry
  createVault(
    name: string,
    symbol: string,
    feePercent: BigNumberish,
    maxTotalAssets: BigNumberish
  ): Promise<EthVault>
  createVaultMock(
    name: string,
    symbol: string,
    feePercent: BigNumberish,
    maxTotalAssets: BigNumberish
  ): Promise<EthVaultMock>
}

export const ethVaultFixture: Fixture<EthVaultFixture> = async function ([
  keeper,
  operator,
  registryOwner,
]): Promise<EthVaultFixture> {
  const validatorsRegistryFactory = await getValidatorsRegistryFactory()
  const validatorsRegistry = await validatorsRegistryFactory.deploy()

  const registryFactory = await ethers.getContractFactory('Registry')
  const registry = (await registryFactory.deploy(registryOwner.address)) as Registry

  const ethVault = await ethers.getContractFactory('EthVault')
  let ethVaultImpl = await upgrades.deployImplementation(ethVault, {
    unsafeAllow: ['delegatecall'],
    constructorArgs: [keeper.address, registry.address, validatorsRegistry.address],
  })

  const ethVaultFactory = await ethers.getContractFactory('EthVaultFactory')
  const factory = (await ethVaultFactory.deploy(ethVaultImpl, registry.address)) as EthVaultFactory
  await registry.connect(registryOwner).addFactory(factory.address)

  const ethVaultMock = await ethers.getContractFactory('EthVaultMock')
  let ethVaultMockImpl = await upgrades.deployImplementation(ethVaultMock, {
    unsafeAllow: ['delegatecall'],
    constructorArgs: [keeper.address, registry.address, validatorsRegistry.address],
  })
  const factoryMock = (await ethVaultFactory.deploy(
    ethVaultMockImpl,
    registry.address
  )) as EthVaultFactory
  await registry.connect(registryOwner).addFactory(factoryMock.address)

  return {
    validatorsRegistry,
    registry,
    vaultFactory: factory,
    vaultFactoryMock: factoryMock,
    createVault: async (
      name: string,
      symbol: string,
      feePercent: BigNumberish,
      maxTotalAssets: BigNumberish
    ): Promise<EthVault> => {
      const tx = await factory
        .connect(operator)
        .createVault(name, symbol, maxTotalAssets, feePercent)
      const receipt = await tx.wait()
      const vaultAddress = receipt.events?.[receipt.events.length - 1].args?.vault as string
      return ethVault.attach(vaultAddress) as EthVault
    },
    createVaultMock: async (name, symbol, feePercent, maxTotalAssets): Promise<EthVaultMock> => {
      const tx = await factoryMock
        .connect(operator)
        .createVault(name, symbol, maxTotalAssets, feePercent)
      const receipt = await tx.wait()
      const vaultAddress = receipt.events?.[receipt.events.length - 1].args?.vault as string
      return ethVaultMock.attach(vaultAddress) as EthVaultMock
    },
  }
}
