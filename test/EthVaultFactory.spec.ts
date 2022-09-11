import { ethers } from 'hardhat'
import { EthVaultFactory } from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { expect } from './shared/expect'

describe('EthVaultFactory', () => {
  let factory: EthVaultFactory

  beforeEach(async () => {
    const ethVaultFactory = await ethers.getContractFactory('EthVaultFactory')
    factory = (await ethVaultFactory.deploy()) as EthVaultFactory
  })

  it('vault deployment gas', async () => {
    await snapshotGasCost(factory.createVault())
  })

  it('predicts vault address', async () => {
    const expectedVaultId = 1
    const expectedAddress = await factory.getVaultAddress(expectedVaultId)

    const tx = await factory.createVault()
    const receipt = await tx.wait()
    const actualAddress = receipt.events?.[0].args?.vault
    const actualVaultId = receipt.events?.[0].args?.vaultId

    expect(actualVaultId).to.be.eq(expectedVaultId)
    expect(actualAddress).to.be.eq(expectedAddress)
  })
})
