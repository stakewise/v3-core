import { ethers } from 'hardhat'
import { Fixture } from 'ethereum-waffle'
import { EthVault, EthVaultFactory, EthVaultMock, EthVaultFactoryMock } from '../../typechain-types'
import { IVaultFactory } from '../../typechain-types'

interface VaultFixture {
  createEthVault(keeper: string, vaultParams: IVaultFactory.ParametersStruct): Promise<EthVault>

  createEthVaultMock(
    keeper: string,
    vaultParams: IVaultFactory.ParametersStruct
  ): Promise<EthVaultMock>
}

export const vaultFixture: Fixture<VaultFixture> = async function (): Promise<VaultFixture> {
  const ethVaultFactory = await ethers.getContractFactory('EthVaultFactory')
  const ethVaultFactoryMock = await ethers.getContractFactory('EthVaultFactoryMock')
  const ethVault = await ethers.getContractFactory('EthVault')
  const ethVaultMock = await ethers.getContractFactory('EthVaultMock')
  return {
    createEthVault: async (keeper: string, vaultParams: IVaultFactory.ParametersStruct) => {
      const factory = (await ethVaultFactory.deploy(keeper)) as EthVaultFactory
      const tx = await factory.createVault(vaultParams)
      const receipt = await tx.wait()
      const vaultAddress = receipt.events?.[0].args?.vault as string
      return ethVault.attach(vaultAddress) as EthVault
    },
    createEthVaultMock: async (keeper: string, vaultParams: IVaultFactory.ParametersStruct) => {
      const factory = (await ethVaultFactoryMock.deploy(keeper)) as EthVaultFactoryMock
      const tx = await factory.createVault(vaultParams)
      const receipt = await tx.wait()
      const vaultAddress = receipt.events?.[0].args?.vault as string
      return ethVaultMock.attach(vaultAddress) as EthVaultMock
    },
  }
}
