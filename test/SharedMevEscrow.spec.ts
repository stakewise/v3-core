import { ethers, waffle } from 'hardhat'
import { Wallet } from 'ethers'
import { SharedMevEscrow, VaultsRegistry } from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { expect } from './shared/expect'
import { parseEther } from 'ethers/lib/utils'
import { ethVaultFixture } from './shared/fixtures'

const createFixtureLoader = waffle.createFixtureLoader

describe('SharedMevEscrow', () => {
  let owner: Wallet, other: Wallet, sharedMevEscrow: SharedMevEscrow, vaultsRegistry: VaultsRegistry

  let loadFixture: ReturnType<typeof createFixtureLoader>

  before('create fixture loader', async () => {
    ;[owner, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([owner])
  })

  beforeEach('deploy fixture', async () => {
    ;({ sharedMevEscrow, vaultsRegistry } = await loadFixture(ethVaultFixture))
  })

  it('vault deployment gas', async () => {
    const sharedMevEscrowFactory = await ethers.getContractFactory('SharedMevEscrow')
    const tx = await sharedMevEscrowFactory.deploy(vaultsRegistry.address)
    await snapshotGasCost(tx.deployTransaction)
  })

  it('only vault can withdraw assets', async () => {
    await expect(sharedMevEscrow.connect(other).harvest(parseEther('1'))).to.be.revertedWith(
      'HarvestFailed'
    )
  })

  it('emits event on transfers', async () => {
    const value = parseEther('1')

    await expect(
      other.sendTransaction({
        to: sharedMevEscrow.address,
        value: value,
      })
    )
      .to.be.emit(sharedMevEscrow, 'MevReceived')
      .withArgs(value)
  })
})
