import { ethers } from 'hardhat'
import { ContractFactory, Wallet } from 'ethers'
import { OwnMevEscrow__factory } from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { expect } from './shared/expect'

describe('OwnMevEscrow', () => {
  let ownMevEscrowFactory: ContractFactory
  let vault: Wallet, other: Wallet

  before(async () => {
    ;[vault, other] = await (ethers as any).getSigners()
    ownMevEscrowFactory = await ethers.getContractFactory('OwnMevEscrow')
  })

  it('vault deployment gas', async () => {
    const contract = await ownMevEscrowFactory.deploy(await vault.getAddress())
    await snapshotGasCost(contract.deploymentTransaction() as any)
  })

  it('only vault can withdraw assets', async () => {
    const tx = await ethers.deployContract('OwnMevEscrow', [await vault.getAddress()])
    const contract = await tx.waitForDeployment()
    const ownMevEscrow = OwnMevEscrow__factory.connect(await contract.getAddress(), other)
    await expect(ownMevEscrow.connect(other).harvest()).to.be.revertedWithCustomError(
      ownMevEscrow,
      'HarvestFailed'
    )
  })

  it('emits event on transfers', async () => {
    const value = ethers.parseEther('1')
    const tx = await ethers.deployContract('OwnMevEscrow', [await vault.getAddress()])
    const contract = await tx.waitForDeployment()
    const ownMevEscrow = OwnMevEscrow__factory.connect(await contract.getAddress(), other)

    await expect(
      other.sendTransaction({
        to: await ownMevEscrow.getAddress(),
        value: value,
      })
    )
      .to.be.emit(ownMevEscrow, 'MevReceived')
      .withArgs(value)
  })
})
