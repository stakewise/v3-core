import { ethers } from 'hardhat'
import { Fixture } from 'ethereum-waffle'
import { EthVault, EthVaultMock } from '../../typechain-types'

interface VaultFixture {
  createEthVault(name: string, symbol: string): Promise<EthVault>

  createEthVaultMock(name: string, symbol: string): Promise<EthVaultMock>
}

export const vaultFixture: Fixture<VaultFixture> = async function (): Promise<VaultFixture> {
  const ethVaultFactory = await ethers.getContractFactory('EthVault')
  const ethVaultMock = await ethers.getContractFactory('EthVaultMock')
  return {
    createEthVault: async (name, symbol) => {
      return (await ethVaultFactory.deploy(name, symbol)) as EthVault
    },
    createEthVaultMock: async (name, symbol) => {
      return (await ethVaultMock.deploy(name, symbol)) as EthVaultMock
    },
  }
}
