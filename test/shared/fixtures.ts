import { ethers } from 'hardhat'
import { Fixture } from 'ethereum-waffle'
import { BigNumberish } from '@ethersproject/bignumber'
import { EthVault, EthVaultFactory, EthVaultMock, EthVaultFactoryMock } from '../../typechain-types'

interface VaultFixture {
  createEthVault(
    operator: string,
    maxTotalAssets: BigNumberish,
    feePercent: BigNumberish
  ): Promise<EthVault>

  createEthVaultMock(
    operator: string,
    maxTotalAssets: BigNumberish,
    feePercent: BigNumberish
  ): Promise<EthVaultMock>
}

export const vaultFixture: Fixture<VaultFixture> = async function (): Promise<VaultFixture> {
  const ethVaultFactory = await ethers.getContractFactory('EthVaultFactory')
  const ethVaultFactoryMock = await ethers.getContractFactory('EthVaultFactoryMock')
  const ethVault = await ethers.getContractFactory('EthVault')
  const ethVaultMock = await ethers.getContractFactory('EthVaultMock')
  return {
    createEthVault: async (
      operator: string,
      maxTotalAssets: BigNumberish,
      feePercent: BigNumberish
    ) => {
      const factory = (await ethVaultFactory.deploy()) as EthVaultFactory
      const tx = await factory.createVault(operator, maxTotalAssets, feePercent)
      const receipt = await tx.wait()
      const vaultAddress = receipt.events?.[0].args?.vault as string
      return ethVault.attach(vaultAddress) as EthVault
    },
    createEthVaultMock: async (
      operator: string,
      maxTotalAssets: BigNumberish,
      feePercent: BigNumberish
    ) => {
      const factory = (await ethVaultFactoryMock.deploy()) as EthVaultFactoryMock
      const tx = await factory.createVault(operator, maxTotalAssets, feePercent)
      const receipt = await tx.wait()
      const vaultAddress = receipt.events?.[0].args?.vault as string
      return ethVaultMock.attach(vaultAddress) as EthVaultMock
    },
  }
}
