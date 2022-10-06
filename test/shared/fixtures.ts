import { ethers, upgrades } from 'hardhat'
import { Fixture } from 'ethereum-waffle'
import { BigNumberish, Contract } from 'ethers'
import { EthVault, EthVaultFactory, EthVaultMock } from '../../typechain-types'
import { getEthRegistryFactory } from './contracts'

interface EthVaultFixture {
  validatorsRegistry: Contract
  vaultFactory: EthVaultFactory
  vaultFactoryMock: EthVaultFactory
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
]): Promise<EthVaultFixture> {
  const ethVaultFactory = await ethers.getContractFactory('EthVaultFactory')
  const ethVault = await ethers.getContractFactory('EthVault')
  const ethVaultMock = await ethers.getContractFactory('EthVaultMock')
  const ethRegistryFactory = await getEthRegistryFactory()
  const registry = await ethRegistryFactory.deploy()

  let ethVaultImpl = await upgrades.deployImplementation(ethVault, {
    unsafeAllow: ['delegatecall'],
    constructorArgs: [keeper.address, registry.address],
  })

  const factory = (await ethVaultFactory.deploy(ethVaultImpl)) as EthVaultFactory

  let ethVaultMockImpl = await upgrades.deployImplementation(ethVaultMock, {
    unsafeAllow: ['delegatecall'],
    constructorArgs: [keeper.address, registry.address],
  })
  const factoryMock = (await ethVaultFactory.deploy(ethVaultMockImpl)) as EthVaultFactory

  return {
    validatorsRegistry: registry,
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
      const vaultAddress = receipt.events?.[2].args?.vault as string
      return ethVault.attach(vaultAddress) as EthVault
    },
    createVaultMock: async (name, symbol, feePercent, maxTotalAssets): Promise<EthVaultMock> => {
      const tx = await factoryMock
        .connect(operator)
        .createVault(name, symbol, maxTotalAssets, feePercent)
      const receipt = await tx.wait()
      const vaultAddress = receipt.events?.[2].args?.vault as string
      return ethVaultMock.attach(vaultAddress) as EthVaultMock
    },
  }
}
