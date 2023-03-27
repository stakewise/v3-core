import { ethers } from 'hardhat'
import { ContractFactory, Wallet } from 'ethers'
import { OwnMevEscrow } from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { expect } from './shared/expect'
import { parseEther } from 'ethers/lib/utils'

describe('OwnMevEscrow', () => {
  let ownMevEscrowFactory: ContractFactory
  let vault: Wallet, other: Wallet

  before(async () => {
    ;[vault, other] = await (ethers as any).getSigners()
    ownMevEscrowFactory = await ethers.getContractFactory('OwnMevEscrow')
  })

  it('vault deployment gas', async () => {
    const tx = await ownMevEscrowFactory.deploy(vault.address)
    await snapshotGasCost(tx.deployTransaction)
  })

  it('only vault can withdraw assets', async () => {
    const mevEscrow = (await ownMevEscrowFactory.deploy(vault.address)) as OwnMevEscrow
    await expect(mevEscrow.connect(other).harvest()).to.be.revertedWith('HarvestFailed')
  })

  it('emits event on transfers', async () => {
    const value = parseEther('1')
    const mevEscrow = (await ownMevEscrowFactory.deploy(vault.address)) as OwnMevEscrow

    await expect(
      other.sendTransaction({
        to: mevEscrow.address,
        value: value,
      })
    )
      .to.be.emit(mevEscrow, 'MevReceived')
      .withArgs(value)
  })
})
