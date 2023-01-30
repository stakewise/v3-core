import { ethers } from 'hardhat'
import { ContractFactory, Wallet } from 'ethers'
import { VaultMevEscrow } from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { expect } from './shared/expect'
import { parseEther } from 'ethers/lib/utils'

describe('VaultMevEscrow', () => {
  let vaultMevEscrowFactory: ContractFactory
  let vault: Wallet, other: Wallet

  before(async () => {
    ;[vault, other] = await (ethers as any).getSigners()
    vaultMevEscrowFactory = await ethers.getContractFactory('VaultMevEscrow')
  })

  it('vault deployment gas', async () => {
    const tx = await vaultMevEscrowFactory.deploy(vault.address)
    await snapshotGasCost(tx.deployTransaction)
  })

  it('only vault can withdraw assets', async () => {
    const mevEscrow = (await vaultMevEscrowFactory.deploy(vault.address)) as VaultMevEscrow
    await expect(mevEscrow.connect(other).withdraw()).to.be.revertedWith('WithdrawalFailed')
  })

  it('emits event on transfers', async () => {
    const value = parseEther('1')
    const mevEscrow = (await vaultMevEscrowFactory.deploy(vault.address)) as VaultMevEscrow

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
