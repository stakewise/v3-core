import { ethers } from 'hardhat'
import { Fixture } from 'ethereum-waffle'
import { Contract } from 'ethers'
import {
  EthVault,
  EthVaultFactory,
  EthVaultFactoryMock,
  EthVaultMock,
  IVaultFactory,
} from '../../typechain-types'
import { getEthRegistryFactory } from './contracts'

interface EthVaultFixture {
  validatorsRegistry: Contract
  vaultFactory: EthVaultFactory
  createVault(vaultParams: IVaultFactory.ParametersStruct): Promise<EthVault>
}

export const ethVaultFixture: Fixture<EthVaultFixture> = async function ([
  keeper,
]): Promise<EthVaultFixture> {
  const ethVaultFactory = await ethers.getContractFactory('EthVaultFactory')
  const ethVault = await ethers.getContractFactory('EthVault')
  const ethRegistryFactory = await getEthRegistryFactory()
  const registry = await ethRegistryFactory.deploy()
  const factory = (await ethVaultFactory.deploy(
    keeper.address,
    registry.address
  )) as EthVaultFactory

  return {
    validatorsRegistry: registry,
    vaultFactory: factory,
    createVault: async (vaultParams: IVaultFactory.ParametersStruct): Promise<EthVault> => {
      const tx = await factory.createVault(vaultParams)
      const receipt = await tx.wait()
      const vaultAddress = receipt.events?.[0].args?.vault as string
      return ethVault.attach(vaultAddress) as EthVault
    },
  }
}

interface EthVaultMockFixture {
  validatorsRegistry: Contract
  vaultFactory: EthVaultFactoryMock
  createVault(vaultParams: IVaultFactory.ParametersStruct): Promise<EthVaultMock>
}

export const ethVaultMockFixture: Fixture<EthVaultMockFixture> = async function ([
  keeper,
]): Promise<EthVaultMockFixture> {
  const ethVaultFactory = await ethers.getContractFactory('EthVaultFactoryMock')
  const ethVault = await ethers.getContractFactory('EthVaultMock')
  const ethRegistryFactory = await getEthRegistryFactory()
  const registry = await ethRegistryFactory.deploy()
  const factory = (await ethVaultFactory.deploy(
    keeper.address,
    registry.address
  )) as EthVaultFactoryMock

  return {
    validatorsRegistry: registry,
    vaultFactory: factory,
    createVault: async (vaultParams: IVaultFactory.ParametersStruct): Promise<EthVaultMock> => {
      const tx = await factory.createVault(vaultParams)
      const receipt = await tx.wait()
      const vaultAddress = receipt.events?.[0].args?.vault as string
      return ethVault.attach(vaultAddress) as EthVaultMock
    },
  }
}
