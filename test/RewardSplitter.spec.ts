import { ethers, waffle } from 'hardhat'
import { BigNumber, Wallet } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import { EthErc20Vault, EthVault, Keeper, RewardSplitter } from '../typechain-types'
import { createRewardSplitterFactory, ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { PANIC_CODES, SECURITY_DEPOSIT, ZERO_ADDRESS } from './shared/constants'
import { collateralizeEthVault, getRewardsRootProof, updateRewards } from './shared/rewards'
import snapshotGasCost from './shared/snapshotGasCost'

const createFixtureLoader = waffle.createFixtureLoader

describe('RewardSplitter', () => {
  let admin: Wallet, owner: Wallet, other: Wallet
  let vault: EthVault, keeper: Keeper, rewardSplitter: RewardSplitter, erc20Vault: EthErc20Vault

  let loadFixture: ReturnType<typeof createFixtureLoader>

  before('create fixture loader', async () => {
    ;[owner, admin, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([owner])
  })

  beforeEach(async () => {
    const fixture = await loadFixture(ethVaultFixture)
    vault = await fixture.createEthVault(admin, {
      capacity: parseEther('1000'),
      feePercent: 1000,
      metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u',
    })
    erc20Vault = await fixture.createEthErc20Vault(admin, {
      capacity: parseEther('1000'),
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
      .callStatic.createRewardSplitter(vault.address)
    await rewardSplitterFactory.connect(admin).createRewardSplitter(vault.address)
    const factory = await ethers.getContractFactory('RewardSplitter')
    rewardSplitter = factory.attach(rewardSplitterAddress) as RewardSplitter
    await vault.connect(admin).setFeeRecipient(rewardSplitter.address)
  })

  describe('increase shares', () => {
    it('fails with zero shares', async () => {
      await expect(
        rewardSplitter.connect(admin).increaseShares(other.address, 0)
      ).to.be.revertedWith('InvalidAmount')
    })

    it('fails with zero account', async () => {
      await expect(
        rewardSplitter.connect(admin).increaseShares(ZERO_ADDRESS, 1)
      ).to.be.revertedWith('InvalidAccount')
    })

    it('fails by not owner', async () => {
      await expect(
        rewardSplitter.connect(other).increaseShares(other.address, 1)
      ).to.be.revertedWith('Ownable: caller is not the owner')
    })

    it('fails when vault not harvested', async () => {
      await rewardSplitter.connect(admin).increaseShares(other.address, 1)
      await updateRewards(
        keeper,
        [{ vault: vault.address, reward: parseEther('1'), unlockedMevReward: 0 }],
        0
      )
      await updateRewards(
        keeper,
        [{ vault: vault.address, reward: parseEther('2'), unlockedMevReward: 0 }],
        0
      )
      await expect(
        rewardSplitter.connect(admin).increaseShares(other.address, 1)
      ).to.be.revertedWith('NotHarvested')
    })

    it('increasing shares does not affect others rewards', async () => {
      await rewardSplitter.connect(admin).increaseShares(other.address, 100)
      await vault.deposit(other.address, ZERO_ADDRESS, {
        value: parseEther('10').sub(SECURITY_DEPOSIT),
      })
      const totalReward = parseEther('1')
      const fee = parseEther('0.1')
      const tree = await updateRewards(
        keeper,
        [{ vault: vault.address, reward: totalReward, unlockedMevReward: 0 }],
        0
      )
      await vault.updateState({
        rewardsRoot: tree.root,
        reward: totalReward,
        unlockedMevReward: 0,
        proof: getRewardsRootProof(tree, {
          vault: vault.address,
          unlockedMevReward: 0,
          reward: totalReward,
        }),
      })
      const feeShares = await vault.convertToShares(fee)
      expect(await vault.feeRecipient()).to.eq(rewardSplitter.address)
      expect(await vault.getShares(rewardSplitter.address)).to.eq(feeShares)

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
      ).to.be.revertedWith('InvalidAmount')
    })

    it('fails with zero account', async () => {
      await expect(
        rewardSplitter.connect(admin).decreaseShares(ZERO_ADDRESS, 1)
      ).to.be.revertedWith('InvalidAccount')
    })

    it('fails by not owner', async () => {
      await expect(
        rewardSplitter.connect(other).decreaseShares(other.address, 1)
      ).to.be.revertedWith('Ownable: caller is not the owner')
    })

    it('fails with amount larger than balance', async () => {
      await expect(
        rewardSplitter.connect(admin).decreaseShares(other.address, shares + 1)
      ).to.be.revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
    })

    it('fails when vault not harvested', async () => {
      await updateRewards(
        keeper,
        [{ vault: vault.address, reward: parseEther('1'), unlockedMevReward: 0 }],
        0
      )
      await updateRewards(
        keeper,
        [{ vault: vault.address, reward: parseEther('2'), unlockedMevReward: 0 }],
        0
      )
      await expect(
        rewardSplitter.connect(admin).decreaseShares(other.address, 1)
      ).to.be.revertedWith('NotHarvested')
    })

    it('decreasing shares does not affect rewards', async () => {
      await rewardSplitter.connect(admin).increaseShares(admin.address, shares)
      await vault.deposit(other.address, ZERO_ADDRESS, {
        value: parseEther('10').sub(SECURITY_DEPOSIT),
      })
      const totalReward = parseEther('1')
      const fee = parseEther('0.1')
      const tree = await updateRewards(
        keeper,
        [{ vault: vault.address, reward: totalReward, unlockedMevReward: 0 }],
        0
      )
      await vault.updateState({
        rewardsRoot: tree.root,
        reward: totalReward,
        unlockedMevReward: 0,
        proof: getRewardsRootProof(tree, {
          vault: vault.address,
          unlockedMevReward: 0,
          reward: totalReward,
        }),
      })
      const feeShares = await vault.convertToShares(fee)
      expect(await vault.feeRecipient()).to.eq(rewardSplitter.address)
      expect(await vault.getShares(rewardSplitter.address)).to.eq(feeShares)

      await rewardSplitter.connect(admin).decreaseShares(admin.address, 1)
      expect(await rewardSplitter.rewardsOf(other.address)).to.eq(feeShares.div(2))
      expect(await rewardSplitter.rewardsOf(admin.address)).to.eq(feeShares.div(2))
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
    const shares = 100
    beforeEach(async () => {
      await rewardSplitter.connect(admin).increaseShares(other.address, shares)
    })

    it('does not sync rewards when up to date', async () => {
      const totalReward = parseEther('1')
      const tree = await updateRewards(
        keeper,
        [{ vault: vault.address, reward: totalReward, unlockedMevReward: 0 }],
        0
      )
      await vault.updateState({
        rewardsRoot: tree.root,
        reward: totalReward,
        unlockedMevReward: 0,
        proof: getRewardsRootProof(tree, {
          vault: vault.address,
          unlockedMevReward: 0,
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
      const totalReward = parseEther('1')
      const tree = await updateRewards(
        keeper,
        [{ vault: vault.address, reward: totalReward, unlockedMevReward: 0 }],
        0
      )
      await vault.updateState({
        rewardsRoot: tree.root,
        reward: totalReward,
        unlockedMevReward: 0,
        proof: getRewardsRootProof(tree, {
          vault: vault.address,
          unlockedMevReward: 0,
          reward: totalReward,
        }),
      })
      expect(await rewardSplitter.canSyncRewards()).to.eq(false)
      await expect(rewardSplitter.syncRewards()).to.not.emit(rewardSplitter, 'RewardsSynced')
    })

    it('anyone can sync rewards', async () => {
      await vault.deposit(other.address, ZERO_ADDRESS, {
        value: parseEther('10').sub(SECURITY_DEPOSIT),
      })
      const totalReward = parseEther('1')
      const fee = parseEther('0.1')
      const tree = await updateRewards(
        keeper,
        [{ vault: vault.address, reward: totalReward, unlockedMevReward: 0 }],
        0
      )
      await vault.updateState({
        rewardsRoot: tree.root,
        reward: totalReward,
        unlockedMevReward: 0,
        proof: getRewardsRootProof(tree, {
          vault: vault.address,
          unlockedMevReward: 0,
          reward: totalReward,
        }),
      })
      const feeShares = await vault.convertToShares(fee)
      expect(await rewardSplitter.canSyncRewards()).to.eq(true)
      const receipt = await rewardSplitter.syncRewards()
      await expect(receipt)
        .to.emit(rewardSplitter, 'RewardsSynced')
        .withArgs(feeShares, feeShares.mul(parseEther('1')).div(shares))
      await snapshotGasCost(receipt)
    })
  })

  describe('withdraw rewards', () => {
    const shares = 100
    let rewards: BigNumber

    beforeEach(async () => {
      await rewardSplitter.connect(admin).increaseShares(other.address, shares)
      const totalReward = parseEther('1')
      const tree = await updateRewards(
        keeper,
        [{ vault: vault.address, reward: totalReward, unlockedMevReward: 0 }],
        0
      )
      await vault.updateState({
        rewardsRoot: tree.root,
        reward: totalReward,
        unlockedMevReward: 0,
        proof: getRewardsRootProof(tree, {
          vault: vault.address,
          unlockedMevReward: 0,
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
        .callStatic.createRewardSplitter(erc20Vault.address)
      await rewardSplitterFactory.connect(admin).createRewardSplitter(erc20Vault.address)

      // collateralize rewards splitter
      const factory = await ethers.getContractFactory('RewardSplitter')
      const rewardSplitter = factory.attach(rewardSplitterAddress) as RewardSplitter
      await erc20Vault.connect(admin).setFeeRecipient(rewardSplitter.address)
      await rewardSplitter.connect(admin).increaseShares(other.address, shares)
      const totalReward = parseEther('1')
      const tree = await updateRewards(
        keeper,
        [{ vault: erc20Vault.address, reward: totalReward, unlockedMevReward: 0 }],
        0
      )
      await erc20Vault.updateState({
        rewardsRoot: tree.root,
        reward: totalReward,
        unlockedMevReward: 0,
        proof: getRewardsRootProof(tree, {
          vault: erc20Vault.address,
          unlockedMevReward: 0,
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
      ).to.be.revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
      await snapshotGasCost(receipt)
    })

    it('can redeem, enter exit queue with multicall', async () => {
      await vault.deposit(other.address, ZERO_ADDRESS, {
        value: parseEther('10').sub(SECURITY_DEPOSIT),
      })
      let totalReward = parseEther('2')
      await updateRewards(
        keeper,
        [{ vault: vault.address, reward: totalReward, unlockedMevReward: 0 }],
        0
      )
      totalReward = parseEther('3')
      const tree = await updateRewards(
        keeper,
        [{ vault: vault.address, reward: totalReward, unlockedMevReward: 0 }],
        0
      )

      const calls: string[] = [
        rewardSplitter.interface.encodeFunctionData('updateVaultState', [
          {
            rewardsRoot: tree.root,
            reward: totalReward,
            unlockedMevReward: 0,
            proof: getRewardsRootProof(tree, {
              vault: vault.address,
              unlockedMevReward: 0,
              reward: totalReward,
            }),
          },
        ]),
        rewardSplitter.interface.encodeFunctionData('syncRewards'),
      ]
      const result = await rewardSplitter.callStatic.multicall([
        ...calls,
        rewardSplitter.interface.encodeFunctionData('rewardsOf', [other.address]),
      ])
      const rewards = rewardSplitter.interface.decodeFunctionResult('rewardsOf', result[2])[0]

      const receipt = await rewardSplitter
        .connect(other)
        .multicall([
          ...calls,
          rewardSplitter.interface.encodeFunctionData('redeem', [rewards.div(2), other.address]),
          rewardSplitter.interface.encodeFunctionData('enterExitQueue', [
            rewards.div(2),
            other.address,
          ]),
        ])
      expect(await rewardSplitter.rewardsOf(other.address)).to.eq(1) // rounding error
      await snapshotGasCost(receipt)
    })
  })
})
