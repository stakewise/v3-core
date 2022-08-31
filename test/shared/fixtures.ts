import { ethers } from 'hardhat'
import { Fixture } from 'ethereum-waffle'
import { EthVault, EthVaultFactory, EthVaultMock } from '../../typechain-types'

interface VaultFixture {
  createEthVault(): Promise<EthVault>

  createEthVaultMock(): Promise<EthVaultMock>
}

export const vaultFixture: Fixture<VaultFixture> = async function (): Promise<VaultFixture> {
  const ethVaultFactory = await ethers.getContractFactory('EthVaultFactory')
  const ethVault = await ethers.getContractFactory('EthVault')
  const ethVaultFactoryMock = await ethers.getContractFactory('EthVaultFactoryMock')
  const ethVaultMock = await ethers.getContractFactory('EthVaultMock')
  return {
    createEthVault: async () => {
      const factory = (await ethVaultFactory.deploy()) as EthVaultFactory
      const tx = await factory.createVault()
      const receipt = await tx.wait()
      const vaultAddress = receipt.events?.[0].args?.vault as string
      return ethVault.attach(vaultAddress) as EthVault
    },
    createEthVaultMock: async () => {
      const factory = (await ethVaultFactoryMock.deploy()) as EthVaultFactory
      const tx = await factory.createVault()
      const receipt = await tx.wait()
      const vaultAddress = receipt.events?.[0].args?.vault as string
      return ethVaultMock.attach(vaultAddress) as EthVaultMock
    },
  }
}
