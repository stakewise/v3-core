import { ethers } from 'hardhat'
import { Wallet } from 'ethers'
import { EthVault, EthVaultFactory } from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { expect } from './shared/expect'

describe('EthVaultFactory', () => {
  const maxTotalAssets = ethers.utils.parseEther('1000')
  const feePercent = 1000
  let operator: Wallet, keeper: Wallet
  let factory: EthVaultFactory

  beforeEach(async () => {
    ;[operator, keeper] = await (ethers as any).getSigners()
    const ethVaultFactory = await ethers.getContractFactory('EthVaultFactory')
    factory = (await ethVaultFactory.deploy(keeper.address)) as EthVaultFactory
  })

  it('vault deployment gas', async () => {
    await snapshotGasCost(factory.createVault(operator.address, maxTotalAssets, feePercent))
  })

  it('creates vault correctly', async () => {
    const expectedAddress = await factory.getVaultAddress(1)
    expect(await factory.lastVaultId()).to.be.eq(0)
    const tx = await factory
      .connect(operator)
      .createVault(operator.address, maxTotalAssets, feePercent)
    const receipt = await tx.wait()
    const actualAddress = receipt.events?.[0].args?.vault
    expect(actualAddress).to.be.eq(expectedAddress)
    expect(tx)
      .to.emit(factory, 'VaultCreated')
      .withArgs(
        operator.address,
        expectedAddress,
        receipt.events?.[0].args?.feesEscrow,
        operator.address,
        maxTotalAssets,
        feePercent
      )
    expect(await factory.lastVaultId()).to.be.eq(1)

    const ethVault = await ethers.getContractFactory('EthVault')
    const vault = ethVault.attach(expectedAddress) as EthVault
    expect(await vault.keeper()).to.be.eq(keeper.address)
  })
})
