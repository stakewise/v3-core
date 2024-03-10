import { ethers } from 'hardhat'
import { Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { GnoSharedMevEscrow, VaultsRegistry } from '../../typechain-types'
import snapshotGasCost from '../shared/snapshotGasCost'
import { expect } from '../shared/expect'

import { gnoVaultFixture } from '../shared/gnoFixtures'

describe('GnoSharedMevEscrow', () => {
  let other: Wallet, sharedMevEscrow: GnoSharedMevEscrow, vaultsRegistry: VaultsRegistry

  beforeEach('deploy fixture', async () => {
    ;[other] = (await (ethers as any).getSigners()).slice(1, 2)
    ;({ sharedMevEscrow, vaultsRegistry } = await loadFixture(gnoVaultFixture))
  })

  it('vault deployment gas', async () => {
    const sharedMevEscrowFactory = await ethers.getContractFactory('GnoSharedMevEscrow')
    const tx = await sharedMevEscrowFactory.deploy(await vaultsRegistry.getAddress())
    await snapshotGasCost(tx.deploymentTransaction() as any)
  })

  it('only vault can withdraw assets', async () => {
    await expect(
      sharedMevEscrow.connect(other).harvest(ethers.parseEther('1'))
    ).to.be.revertedWithCustomError(sharedMevEscrow, 'HarvestFailed')
  })

  it('emits event on transfers', async () => {
    const value = ethers.parseEther('1')

    await expect(
      other.sendTransaction({
        to: await sharedMevEscrow.getAddress(),
        value: value,
      })
    )
      .to.be.emit(sharedMevEscrow, 'MevReceived')
      .withArgs(value)
  })
})
