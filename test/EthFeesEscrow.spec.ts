import { ethers } from 'hardhat'
import { ContractFactory, Wallet } from 'ethers'
import { EthFeesEscrow } from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { expect } from './shared/expect'
import { parseEther } from 'ethers/lib/utils'

describe('EthFeesEscrow', () => {
  let ethFeesEscrowFactory: ContractFactory
  let vault: Wallet, other: Wallet

  before(async () => {
    ;[vault, other] = await (ethers as any).getSigners()
    ethFeesEscrowFactory = await ethers.getContractFactory('EthFeesEscrow')
  })

  it('vault deployment gas', async () => {
    const tx = await ethFeesEscrowFactory.deploy(vault.address)
    await snapshotGasCost(tx.deployTransaction)
  })

  it('only vault can withdraw assets', async () => {
    const feesEscrow = (await ethFeesEscrowFactory.deploy(vault.address)) as EthFeesEscrow
    await expect(feesEscrow.connect(other).withdraw()).to.be.revertedWith('WithdrawalFailed()')
  })

  it('emits event on transfers', async () => {
    const value = parseEther('1')
    const feesEscrow = (await ethFeesEscrowFactory.deploy(vault.address)) as EthFeesEscrow

    await expect(
      other.sendTransaction({
        to: feesEscrow.address,
        value: value,
      })
    )
      .to.be.emit(feesEscrow, 'Deposited')
      .withArgs(value)
    expect(await feesEscrow.balance()).to.eq(value)
  })
})
