import { ethers } from 'hardhat'
import { Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  EthVault,
  RewardSplitterFactory__factory,
  RewardSplitter__factory,
  RewardSplitterFactory,
} from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { createRewardSplitterFactory, ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'

describe('RewardSplitterFactory', () => {
  let admin: Wallet
  let vault: EthVault, rewardSplitterFactory: RewardSplitterFactory

  before('create fixture loader', async () => {
    ;[admin] = (await (ethers as any).getSigners()).slice(1, 2)
  })

  beforeEach(async () => {
    const fixture = await loadFixture(ethVaultFixture)
    vault = await fixture.createEthVault(admin, {
      capacity: ethers.parseEther('1000'),
      feePercent: 1000,
      metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u',
    })
    rewardSplitterFactory = await createRewardSplitterFactory()
  })

  it('splitter deployment gas', async () => {
    const receipt = await rewardSplitterFactory
      .connect(admin)
      .createRewardSplitter(await vault.getAddress())
    await snapshotGasCost(receipt)
  })

  it('factory deploys correctly', async () => {
    let factory = await ethers.getContractFactory('RewardSplitter')
    const rewardSplitterImpl = await factory.deploy()
    const rewardSplitterImplAddress = await rewardSplitterImpl.getAddress()

    factory = await ethers.getContractFactory('RewardSplitterFactory')
    const rewardsFactory = RewardSplitterFactory__factory.connect(
      await (await factory.deploy(rewardSplitterImplAddress)).getAddress(),
      admin
    )
    expect(await rewardsFactory.implementation()).to.eq(rewardSplitterImplAddress)
  })

  it('splitter deploys correctly', async () => {
    const rewardSplitterAddress = await rewardSplitterFactory
      .connect(admin)
      .createRewardSplitter.staticCall(await vault.getAddress())
    const receipt = await rewardSplitterFactory
      .connect(admin)
      .createRewardSplitter(await vault.getAddress())
    await expect(receipt)
      .to.emit(rewardSplitterFactory, 'RewardSplitterCreated')
      .withArgs(admin.address, await vault.getAddress(), rewardSplitterAddress)

    const rewardSplitter = RewardSplitter__factory.connect(rewardSplitterAddress, admin)
    expect(await rewardSplitter.vault()).to.eq(await vault.getAddress())
    expect(await rewardSplitter.owner()).to.eq(admin.address)
    expect(await rewardSplitter.totalShares()).to.eq(0)
  })
})
