import { ethers } from 'hardhat'
import { Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  EthErc20Vault,
  EthVault,
  Keeper,
  RewardSplitter,
  RewardSplitter__factory,
} from '../typechain-types'
import { createRewardSplitterFactory, ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { PANIC_CODES, SECURITY_DEPOSIT, ZERO_ADDRESS } from './shared/constants'
import { collateralizeEthVault, getRewardsRootProof, updateRewards } from './shared/rewards'
import snapshotGasCost from './shared/snapshotGasCost'

describe('RewardSplitter', () => {
  let admin: Wallet, other: Wallet
  let vault: EthVault, keeper: Keeper, rewardSplitter: RewardSplitter, erc20Vault: EthErc20Vault

  before('create fixture loader', async () => {
    ;[admin, other] = (await (ethers as any).getSigners()).slice(1, 3)
  })

  beforeEach(async () => {
    const fixture = await loadFixture(ethVaultFixture)
    vault = await fixture.createEthVault(admin, {
      capacity: ethers.parseEther('1000'),
      feePercent: 1000,
      metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u',
    })
    erc20Vault = await fixture.createEthErc20Vault(admin, {
      capacity: ethers.parseEther('1000'),
      feePercent: 1000,
      metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u',
      name: 'SW ETH Vault',
      symbol: 'SW-ETH-1',
    })
    keeper = fixture.keeper
    await collateralizeEthVault(vault, keeper, fixture.validatorsRegistry, admin)
    await collateralizeEthVault(erc20Vault, keeper, fixture.validatorsRegistry, admin)

    const rewardSplitterFactory = await createRewardSplitterFactory()
    const rewardSplitterAddress = await rewardSplitterFactory
      .connect(admin)
      .createRewardSplitter.staticCall(await vault.getAddress())
    await rewardSplitterFactory.connect(admin).createRewardSplitter(await vault.getAddress())
    rewardSplitter = RewardSplitter__factory.connect(rewardSplitterAddress, admin)
    await vault.connect(admin).setFeeRecipient(rewardSplitterAddress)
  })

  describe('increase shares', () => {
    it('fails with zero shares', async () => {
      await expect(
        rewardSplitter.connect(admin).increaseShares(other.address, 0)
      ).to.be.revertedWithCustomError(rewardSplitter, 'InvalidAmount')
    })

    it('fails with zero account', async () => {
      await expect(
        rewardSplitter.connect(admin).increaseShares(ZERO_ADDRESS, 1)
      ).to.be.revertedWithCustomError(rewardSplitter, 'InvalidAccount')
    })

    it('fails by not owner', async () => {
      await expect(
        rewardSplitter.connect(other).increaseShares(other.address, 1)
      ).to.be.revertedWithCustomError(rewardSplitter, 'OwnableUnauthorizedAccount')
    })

    it('fails when vault not harvested', async () => {
      await rewardSplitter.connect(admin).increaseShares(other.address, 1)
      await updateRewards(
        keeper,
        [
          {
            vault: await vault.getAddress(),
            reward: ethers.parseEther('1'),
            unlockedMevReward: 0n,
          },
        ],
        0
      )
      await updateRewards(
        keeper,
        [
          {
            vault: await vault.getAddress(),
            reward: ethers.parseEther('2'),
            unlockedMevReward: 0n,
          },
        ],
        0
      )
      await expect(
        rewardSplitter.connect(admin).increaseShares(other.address, 1)
      ).to.be.revertedWithCustomError(rewardSplitter, 'NotHarvested')
    })

    it('increasing shares does not affect others rewards', async () => {
      await rewardSplitter.connect(admin).increaseShares(other.address, 100)
      await vault.deposit(other.address, ZERO_ADDRESS, {
        value: ethers.parseEther('10') - SECURITY_DEPOSIT,
      })
      const totalReward = ethers.parseEther('1')
      const fee = ethers.parseEther('0.1')
      const tree = await updateRewards(
        keeper,
        [{ vault: await vault.getAddress(), reward: totalReward, unlockedMevReward: 0n }],
        0
      )
      await vault.updateState({
        rewardsRoot: tree.root,
        reward: totalReward,
        unlockedMevReward: 0n,
        proof: getRewardsRootProof(tree, {
          vault: await vault.getAddress(),
          unlockedMevReward: 0n,
          reward: totalReward,
        }),
      })
      const feeShares = await vault.convertToShares(fee)
      expect(await vault.feeRecipient()).to.eq(await rewardSplitter.getAddress())
      expect(await vault.getShares(await rewardSplitter.getAddress())).to.eq(feeShares)

      await rewardSplitter.connect(admin).increaseShares(admin.address, 100)
      expect(await rewardSplitter.rewardsOf(other.address)).to.eq(feeShares)
      expect(await rewardSplitter.rewardsOf(admin.address)).to.eq(0)
    })

    it('owner can increase shares', async () => {
      const shares = 100
      const receipt = await rewardSplitter.connect(admin).increaseShares(other.address, shares)
      expect(await rewardSplitter.sharesOf(other.address)).to.eq(shares)
      expect(await rewardSplitter.totalShares()).to.eq(shares)
      await expect(receipt)
        .to.emit(rewardSplitter, 'SharesIncreased')
        .withArgs(other.address, shares)
      await snapshotGasCost(receipt)
    })
  })

  describe('decrease shares', () => {
    const shares = 100
    beforeEach(async () => {
      await rewardSplitter.connect(admin).increaseShares(other.address, shares)
    })

    it('fails with zero shares', async () => {
      await expect(
        rewardSplitter.connect(admin).decreaseShares(other.address, 0)
      ).to.be.revertedWithCustomError(rewardSplitter, 'InvalidAmount')
    })

    it('fails with zero account', async () => {
      await expect(
        rewardSplitter.connect(admin).decreaseShares(ZERO_ADDRESS, 1)
      ).to.be.revertedWithCustomError(rewardSplitter, 'InvalidAccount')
    })

    it('fails by not owner', async () => {
      await expect(
        rewardSplitter.connect(other).decreaseShares(other.address, 1)
      ).to.be.revertedWithCustomError(rewardSplitter, 'OwnableUnauthorizedAccount')
    })

    it('fails with amount larger than balance', async () => {
      await expect(
        rewardSplitter.connect(admin).decreaseShares(other.address, shares + 1)
      ).to.be.revertedWithPanic(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
    })

    it('fails when vault not harvested', async () => {
      await updateRewards(
        keeper,
        [
          {
            vault: await vault.getAddress(),
            reward: ethers.parseEther('1'),
            unlockedMevReward: 0n,
          },
        ],
        0
      )
      await updateRewards(
        keeper,
        [
          {
            vault: await vault.getAddress(),
            reward: ethers.parseEther('2'),
            unlockedMevReward: 0n,
          },
        ],
        0
      )
      await expect(
        rewardSplitter.connect(admin).decreaseShares(other.address, 1)
      ).to.be.revertedWithCustomError(rewardSplitter, 'NotHarvested')
    })

    it('decreasing shares does not affect rewards', async () => {
      await rewardSplitter.connect(admin).increaseShares(admin.address, shares)
      await vault.deposit(other.address, ZERO_ADDRESS, {
        value: ethers.parseEther('10') - SECURITY_DEPOSIT,
      })
      const totalReward = ethers.parseEther('1')
      const fee = ethers.parseEther('0.1')
      const tree = await updateRewards(
        keeper,
        [{ vault: await vault.getAddress(), reward: totalReward, unlockedMevReward: 0n }],
        0
      )
      await vault.updateState({
        rewardsRoot: tree.root,
        reward: totalReward,
        unlockedMevReward: 0n,
        proof: getRewardsRootProof(tree, {
          vault: await vault.getAddress(),
          unlockedMevReward: 0n,
          reward: totalReward,
        }),
      })
      const feeShares = await vault.convertToShares(fee)
      expect(await vault.feeRecipient()).to.eq(await rewardSplitter.getAddress())
      expect(await vault.getShares(await rewardSplitter.getAddress())).to.eq(feeShares)

      await rewardSplitter.connect(admin).decreaseShares(admin.address, 1)
      expect(await rewardSplitter.rewardsOf(other.address)).to.eq(feeShares / 2n)
      expect(await rewardSplitter.rewardsOf(admin.address)).to.eq(feeShares / 2n)
    })

    it('owner can decrease shares', async () => {
      const receipt = await rewardSplitter.connect(admin).decreaseShares(other.address, 1)
      const newShares = shares - 1

      expect(await rewardSplitter.sharesOf(other.address)).to.eq(newShares)
      expect(await rewardSplitter.totalShares()).to.eq(newShares)
      await expect(receipt).to.emit(rewardSplitter, 'SharesDecreased').withArgs(other.address, 1)
      await snapshotGasCost(receipt)
    })
  })

  describe('sync rewards', () => {
    const shares = 100n
    beforeEach(async () => {
      await rewardSplitter.connect(admin).increaseShares(other.address, shares)
    })

    it('does not sync rewards when up to date', async () => {
      const totalReward = ethers.parseEther('1')
      const tree = await updateRewards(
        keeper,
        [{ vault: await vault.getAddress(), reward: totalReward, unlockedMevReward: 0n }],
        0
      )
      await vault.updateState({
        rewardsRoot: tree.root,
        reward: totalReward,
        unlockedMevReward: 0n,
        proof: getRewardsRootProof(tree, {
          vault: await vault.getAddress(),
          unlockedMevReward: 0n,
          reward: totalReward,
        }),
      })
      expect(await rewardSplitter.canSyncRewards()).to.eq(true)
      await rewardSplitter.syncRewards()
      expect(await rewardSplitter.canSyncRewards()).to.eq(false)
      await expect(rewardSplitter.syncRewards()).to.not.emit(rewardSplitter, 'RewardsSynced')
    })

    it('does not sync rewards with zero total shares', async () => {
      await rewardSplitter.connect(admin).decreaseShares(other.address, shares)
      const totalReward = ethers.parseEther('1')
      const tree = await updateRewards(
        keeper,
        [{ vault: await vault.getAddress(), reward: totalReward, unlockedMevReward: 0n }],
        0
      )
      await vault.updateState({
        rewardsRoot: tree.root,
        reward: totalReward,
        unlockedMevReward: 0n,
        proof: getRewardsRootProof(tree, {
          vault: await vault.getAddress(),
          unlockedMevReward: 0n,
          reward: totalReward,
        }),
      })
      expect(await rewardSplitter.canSyncRewards()).to.eq(false)
      await expect(rewardSplitter.syncRewards()).to.not.emit(rewardSplitter, 'RewardsSynced')
    })

    it('anyone can sync rewards', async () => {
      await vault.deposit(other.address, ZERO_ADDRESS, {
        value: ethers.parseEther('10') - SECURITY_DEPOSIT,
      })
      const totalReward = ethers.parseEther('1')
      const fee = ethers.parseEther('0.1')
      const tree = await updateRewards(
        keeper,
        [{ vault: await vault.getAddress(), reward: totalReward, unlockedMevReward: 0n }],
        0
      )
      await vault.updateState({
        rewardsRoot: tree.root,
        reward: totalReward,
        unlockedMevReward: 0n,
        proof: getRewardsRootProof(tree, {
          vault: await vault.getAddress(),
          unlockedMevReward: 0n,
          reward: totalReward,
        }),
      })
      const feeShares = await vault.convertToShares(fee)
      expect(await rewardSplitter.canSyncRewards()).to.eq(true)
      const receipt = await rewardSplitter.syncRewards()
      await expect(receipt)
        .to.emit(rewardSplitter, 'RewardsSynced')
        .withArgs(feeShares, (feeShares * ethers.parseEther('1')) / shares)
      await snapshotGasCost(receipt)
    })
  })

  describe('withdraw rewards', () => {
    const shares = 100
    let rewards: bigint

    beforeEach(async () => {
      await rewardSplitter.connect(admin).increaseShares(other.address, shares)
      const totalReward = ethers.parseEther('1')
      const tree = await updateRewards(
        keeper,
        [{ vault: await vault.getAddress(), reward: totalReward, unlockedMevReward: 0n }],
        0
      )
      await vault.updateState({
        rewardsRoot: tree.root,
        reward: totalReward,
        unlockedMevReward: 0n,
        proof: getRewardsRootProof(tree, {
          vault: await vault.getAddress(),
          unlockedMevReward: 0n,
          reward: totalReward,
        }),
      })
      await rewardSplitter.syncRewards()
      rewards = await rewardSplitter.rewardsOf(other.address)
    })

    it('fails to claim vault tokens for not ERC-20 vault', async () => {
      await expect(rewardSplitter.connect(other).claimVaultTokens(rewards, other.address)).to.be
        .reverted
    })

    it('can claim vault tokens for ERC-20 vault', async () => {
      // create rewards splitter
      const rewardSplitterFactory = await createRewardSplitterFactory()
      const rewardSplitterAddress = await rewardSplitterFactory
        .connect(admin)
        .createRewardSplitter.staticCall(await erc20Vault.getAddress())
      await rewardSplitterFactory.connect(admin).createRewardSplitter(await erc20Vault.getAddress())

      // collateralize rewards splitter
      const rewardSplitter = RewardSplitter__factory.connect(rewardSplitterAddress, admin)
      await erc20Vault.connect(admin).setFeeRecipient(await rewardSplitter.getAddress())
      await rewardSplitter.connect(admin).increaseShares(other.address, shares)
      const totalReward = ethers.parseEther('1')
      const tree = await updateRewards(
        keeper,
        [{ vault: await erc20Vault.getAddress(), reward: totalReward, unlockedMevReward: 0n }],
        0
      )
      await erc20Vault.updateState({
        rewardsRoot: tree.root,
        reward: totalReward,
        unlockedMevReward: 0n,
        proof: getRewardsRootProof(tree, {
          vault: await erc20Vault.getAddress(),
          unlockedMevReward: 0n,
          reward: totalReward,
        }),
      })
      await rewardSplitter.syncRewards()
      const rewards = await rewardSplitter.rewardsOf(other.address)

      const receipt = await rewardSplitter.connect(other).claimVaultTokens(rewards, other.address)
      await expect(receipt)
        .to.emit(rewardSplitter, 'RewardsWithdrawn')
        .withArgs(other.address, rewards)
      expect(await rewardSplitter.rewardsOf(other.address)).to.eq(0)

      // second claim should fail
      await expect(
        rewardSplitter.connect(other).claimVaultTokens(rewards, other.address)
      ).to.be.revertedWithPanic(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
      await snapshotGasCost(receipt)
    })

    it('can enter exit queue with multicall', async () => {
      await vault.deposit(other.address, ZERO_ADDRESS, {
        value: ethers.parseEther('10') - SECURITY_DEPOSIT,
      })
      let totalReward = ethers.parseEther('2')
      await updateRewards(
        keeper,
        [{ vault: await vault.getAddress(), reward: totalReward, unlockedMevReward: 0n }],
        0
      )
      totalReward = ethers.parseEther('3')
      const tree = await updateRewards(
        keeper,
        [{ vault: await vault.getAddress(), reward: totalReward, unlockedMevReward: 0n }],
        0
      )

      const calls: string[] = [
        rewardSplitter.interface.encodeFunctionData('updateVaultState', [
          {
            rewardsRoot: tree.root,
            reward: totalReward,
            unlockedMevReward: 0n,
            proof: getRewardsRootProof(tree, {
              vault: await vault.getAddress(),
              unlockedMevReward: 0n,
              reward: totalReward,
            }),
          },
        ]),
        rewardSplitter.interface.encodeFunctionData('syncRewards'),
      ]
      const result = await rewardSplitter.multicall.staticCall([
        ...calls,
        rewardSplitter.interface.encodeFunctionData('rewardsOf', [other.address]),
      ])
      const rewards = rewardSplitter.interface.decodeFunctionResult('rewardsOf', result[2])[0]

      const receipt = await rewardSplitter
        .connect(other)
        .multicall([
          ...calls,
          rewardSplitter.interface.encodeFunctionData('enterExitQueue', [rewards, other.address]),
        ])
      expect(await rewardSplitter.rewardsOf(other.address)).to.eq(0)
      await snapshotGasCost(receipt)
    })
  })
})
