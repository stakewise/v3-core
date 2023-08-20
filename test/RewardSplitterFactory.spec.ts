import { ethers, waffle } from 'hardhat'
import { Wallet } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import { EthVault, RewardSplitter, RewardSplitterFactory } from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { createRewardSplitterFactory, ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'

const createFixtureLoader = waffle.createFixtureLoader

describe('RewardSplitterFactory', () => {
  let admin: Wallet, owner: Wallet
  let vault: EthVault, rewardSplitterFactory: RewardSplitterFactory

  let loadFixture: ReturnType<typeof createFixtureLoader>

  before('create fixture loader', async () => {
    ;[owner, admin] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([owner])
  })

  beforeEach(async () => {
    const fixture = await loadFixture(ethVaultFixture)
    vault = await fixture.createEthVault(admin, {
      capacity: parseEther('1000'),
      feePercent: 1000,
      metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u',
    })
    rewardSplitterFactory = await createRewardSplitterFactory()
  })

  it('splitter deployment gas', async () => {
    const receipt = await rewardSplitterFactory.connect(admin).createRewardSplitter(vault.address)
    await snapshotGasCost(receipt)
  })

  it('factory deploys correctly', async () => {
    let factory = await ethers.getContractFactory('RewardSplitter')
    const rewardSplitterImpl = await factory.deploy()

    factory = await ethers.getContractFactory('RewardSplitterFactory')
    const rewardsFactory = (await factory.deploy(
      rewardSplitterImpl.address
    )) as RewardSplitterFactory
    expect(await rewardsFactory.implementation()).to.eq(rewardSplitterImpl.address)
  })

  it('splitter deploys correctly', async () => {
    const rewardSplitterAddress = await rewardSplitterFactory
      .connect(admin)
      .callStatic.createRewardSplitter(vault.address)
    const receipt = await rewardSplitterFactory.connect(admin).createRewardSplitter(vault.address)
    await expect(receipt)
      .to.emit(rewardSplitterFactory, 'RewardSplitterCreated')
      .withArgs(admin.address, vault.address, rewardSplitterAddress)

    const factory = await ethers.getContractFactory('RewardSplitter')
    const rewardSplitter = (await factory.attach(rewardSplitterAddress)) as RewardSplitter
    expect(await rewardSplitter.vault()).to.eq(vault.address)
    expect(await rewardSplitter.owner()).to.eq(admin.address)
    expect(await rewardSplitter.totalShares()).to.eq(0)
  })
})
