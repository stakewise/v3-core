import { ethers } from 'hardhat'
import { ContractFactory, Wallet } from 'ethers'
import { EthFeesEscrow } from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { expect } from './shared/expect'

describe('EthFeesEscrow', () => {
  let ethFeesEscrowFactory: ContractFactory

  before(async () => {
    ethFeesEscrowFactory = await ethers.getContractFactory('EthFeesEscrow')
  })

  it('vault deployment gas', async () => {
    const tx = await ethFeesEscrowFactory.deploy()
    await snapshotGasCost(tx.deployTransaction)
  })

  it('only vault can withdraw assets', async () => {
    const feesEscrow = (await ethFeesEscrowFactory.deploy()) as EthFeesEscrow
    const other: Wallet = (await (ethers as any).getSigners())[1]
    await expect(feesEscrow.connect(other).withdraw()).to.be.revertedWith('WithdrawalFailed()')
  })
})
