import { ethers, waffle } from 'hardhat'
import { BigNumber, Contract, Wallet } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import {
  EthVault,
  IKeeperRewards,
  Keeper,
  Oracles,
  SharedMevEscrow,
  OsToken,
} from '../typechain-types'
import { ThenArg } from '../helpers/types'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import {
  MAX_AVG_REWARD_PER_SECOND,
  ORACLES,
  REWARDS_DELAY,
  ZERO_ADDRESS,
  ZERO_BYTES32,
} from './shared/constants'
import snapshotGasCost from './shared/snapshotGasCost'
import { getKeeperRewardsUpdateData, getRewardsRootProof, VaultReward } from './shared/rewards'
import { increaseTime, setBalance } from './shared/utils'
import { registerEthValidator } from './shared/validators'

const createFixtureLoader = waffle.createFixtureLoader

describe('KeeperRewards', () => {
  const capacity = parseEther('1000')
  const feePercent = 1000
  const name = 'SW ETH Vault'
  const symbol = 'SW-ETH-1'
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createVault']
  let getSignatures: ThenArg<ReturnType<typeof ethVaultFixture>>['getSignatures']

  let owner: Wallet, admin: Wallet, oracle: Wallet
  let keeper: Keeper,
    oracles: Oracles,
    validatorsRegistry: Contract,
    sharedMevEscrow: SharedMevEscrow,
    osToken: OsToken

  before('create fixture loader', async () => {
    ;[admin, owner] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([owner])
    oracle = new Wallet(ORACLES[0], await waffle.provider)
  })

  beforeEach(async () => {
    ;({
      oracles,
      keeper,
      createVault,
      validatorsRegistry,
      sharedMevEscrow,
      osToken,
      getSignatures,
    } = await loadFixture(ethVaultFixture))
    await setBalance(oracle.address, parseEther('10000'))
  })

  describe('update rewards', () => {
    let vaultReward: VaultReward
    let rewardsUpdateParams: IKeeperRewards.RewardsUpdateParamsStruct
    let vault: EthVault

    beforeEach(async () => {
      vault = await createVault(admin, {
        capacity,
        feePercent,
        name,
        symbol,
        metadataIpfsHash,
      })
      vaultReward = {
        reward: parseEther('5'),
        unlockedMevReward: parseEther('1'),
        vault: vault.address,
      }
      const rewardsUpdate = getKeeperRewardsUpdateData([vaultReward], oracles)
      rewardsUpdateParams = {
        rewardsRoot: rewardsUpdate.root,
        updateTimestamp: rewardsUpdate.updateTimestamp,
        rewardsIpfsHash: rewardsUpdate.ipfsHash,
        avgRewardPerSecond: rewardsUpdate.avgRewardPerSecond,
        signatures: getSignatures(rewardsUpdate.signingData),
      }
    })

    it('fails with invalid root', async () => {
      await expect(
        keeper.connect(oracle).updateRewards({ ...rewardsUpdateParams, rewardsRoot: ZERO_BYTES32 })
      ).to.be.revertedWith('InvalidRewardsRoot')

      // check can't set to previous rewards root
      await keeper.connect(oracle).updateRewards(rewardsUpdateParams)
      await increaseTime(REWARDS_DELAY)
      await expect(
        keeper.connect(oracle).updateRewards({ ...rewardsUpdateParams, rewardsRoot: ZERO_BYTES32 })
      ).to.be.revertedWith('InvalidRewardsRoot')
    })

    it('fails with invalid IPFS hash', async () => {
      await expect(
        keeper
          .connect(oracle)
          .updateRewards({ ...rewardsUpdateParams, rewardsIpfsHash: ZERO_BYTES32 })
      ).to.be.revertedWith('InvalidOracle')
    })

    it('fails with invalid avgRewardPerSecond', async () => {
      await expect(
        keeper.connect(oracle).updateRewards({
          ...rewardsUpdateParams,
          avgRewardPerSecond: MAX_AVG_REWARD_PER_SECOND.add(1),
        })
      ).to.be.revertedWith('InvalidAvgRewardPerSecond')
    })

    it('fails with invalid nonce', async () => {
      await keeper.connect(oracle).updateRewards(rewardsUpdateParams)

      const newVaultReward = {
        reward: parseEther('3'),
        unlockedMevReward: parseEther('2'),
        vault: vault.address,
      }
      const newRewardsUpdate = getKeeperRewardsUpdateData([newVaultReward], oracles)
      await increaseTime(REWARDS_DELAY)
      await expect(
        keeper.connect(oracle).updateRewards({
          rewardsRoot: newRewardsUpdate.root,
          rewardsIpfsHash: newRewardsUpdate.ipfsHash,
          updateTimestamp: newRewardsUpdate.updateTimestamp,
          avgRewardPerSecond: newRewardsUpdate.avgRewardPerSecond,
          signatures: getSignatures(newRewardsUpdate.signingData),
        })
      ).to.be.revertedWith('InvalidOracle')
    })

    it('fails if too early', async () => {
      await keeper.connect(oracle).updateRewards(rewardsUpdateParams)
      const newVaultReward = {
        reward: parseEther('5'),
        unlockedMevReward: parseEther('1'),
        vault: vault.address,
      }
      const newRewardsUpdate = getKeeperRewardsUpdateData([newVaultReward], oracles, {
        nonce: 2,
        updateTimestamp: '1680255895',
      })
      expect(await keeper.canUpdateRewards()).to.eq(false)
      await expect(
        keeper.connect(oracle).updateRewards({
          rewardsRoot: newRewardsUpdate.root,
          rewardsIpfsHash: newRewardsUpdate.ipfsHash,
          updateTimestamp: newRewardsUpdate.updateTimestamp,
          avgRewardPerSecond: newRewardsUpdate.avgRewardPerSecond,
          signatures: getSignatures(newRewardsUpdate.signingData),
        })
      ).to.be.revertedWith('TooEarlyUpdate')
    })

    it('succeeds', async () => {
      expect(await keeper.lastRewardsTimestamp()).to.eq(0)
      expect(await keeper.canUpdateRewards()).to.eq(true)
      let receipt = await keeper.connect(oracle).updateRewards(rewardsUpdateParams)
      await expect(receipt)
        .to.emit(keeper, 'RewardsUpdated')
        .withArgs(
          oracle.address,
          rewardsUpdateParams.rewardsRoot,
          rewardsUpdateParams.avgRewardPerSecond,
          rewardsUpdateParams.updateTimestamp,
          1,
          rewardsUpdateParams.rewardsIpfsHash
        )
      await expect(receipt)
        .to.emit(osToken, 'AvgRewardPerSecondUpdated')
        .withArgs(rewardsUpdateParams.avgRewardPerSecond)
      expect(await keeper.prevRewardsRoot()).to.eq(ZERO_BYTES32)
      expect(await keeper.rewardsRoot()).to.eq(rewardsUpdateParams.rewardsRoot)
      expect(await keeper.rewardsNonce()).to.eq(2)
      expect(await osToken.avgRewardPerSecond()).to.eq(rewardsUpdateParams.avgRewardPerSecond)
      expect(await keeper.lastRewardsTimestamp()).to.not.eq(0)
      expect(await keeper.canUpdateRewards()).to.eq(false)
      await snapshotGasCost(receipt)

      // check keeps previous rewards root
      const newVaultReward = {
        reward: parseEther('3'),
        unlockedMevReward: parseEther('2'),
        vault: vault.address,
      }
      const newRewardsUpdate = getKeeperRewardsUpdateData([newVaultReward], oracles, {
        nonce: 2,
        updateTimestamp: '1670256000',
      })
      await increaseTime(REWARDS_DELAY)
      receipt = await keeper.connect(oracle).updateRewards({
        rewardsRoot: newRewardsUpdate.root,
        rewardsIpfsHash: newRewardsUpdate.ipfsHash,
        updateTimestamp: newRewardsUpdate.updateTimestamp,
        avgRewardPerSecond: newRewardsUpdate.avgRewardPerSecond,
        signatures: getSignatures(newRewardsUpdate.signingData),
      })
      await expect(receipt)
        .to.emit(keeper, 'RewardsUpdated')
        .withArgs(
          oracle.address,
          newRewardsUpdate.root,
          newRewardsUpdate.avgRewardPerSecond,
          newRewardsUpdate.updateTimestamp,
          2,
          newRewardsUpdate.ipfsHash
        )
      expect(await keeper.prevRewardsRoot()).to.eq(rewardsUpdateParams.rewardsRoot)
      expect(await keeper.rewardsRoot()).to.eq(newRewardsUpdate.root)
      expect(await keeper.rewardsNonce()).to.eq(3)
      await snapshotGasCost(receipt)
    })
  })

  describe('is harvest required', () => {
    let vault: EthVault

    beforeEach(async () => {
      vault = await createVault(admin, {
        capacity,
        feePercent,
        name,
        symbol,
        metadataIpfsHash,
      })
    })

    it('returns false for uncollateralized vault', async () => {
      expect(await keeper.isCollateralized(vault.address)).to.equal(false)
      expect(await keeper.isHarvestRequired(vault.address)).to.equal(false)
      expect(await keeper.canHarvest(vault.address)).to.equal(false)
    })

    it('returns true for collateralized two times unharvested vault', async () => {
      // collateralize vault
      const validatorDeposit = parseEther('32')
      await vault.connect(admin).deposit(admin.address, ZERO_ADDRESS, { value: validatorDeposit })
      await registerEthValidator(vault, oracles, keeper, validatorsRegistry, admin, getSignatures)

      expect(await keeper.isCollateralized(vault.address)).to.equal(true)
      expect(await keeper.canHarvest(vault.address)).to.equal(false)
      expect(await keeper.isHarvestRequired(vault.address)).to.equal(false)

      // update rewards first time
      let newVaultReward = {
        reward: parseEther('3'),
        unlockedMevReward: parseEther('0.5'),
        vault: vault.address,
      }
      let newRewardsUpdate = getKeeperRewardsUpdateData([newVaultReward], oracles, {
        updateTimestamp: '1670258895',
      })
      await keeper.connect(oracle).updateRewards({
        rewardsRoot: newRewardsUpdate.root,
        rewardsIpfsHash: newRewardsUpdate.ipfsHash,
        updateTimestamp: newRewardsUpdate.updateTimestamp,
        avgRewardPerSecond: newRewardsUpdate.avgRewardPerSecond,

        signatures: getSignatures(newRewardsUpdate.signingData),
      })

      expect(await keeper.isCollateralized(vault.address)).to.equal(true)
      expect(await keeper.canHarvest(vault.address)).to.equal(true)
      expect(await keeper.isHarvestRequired(vault.address)).to.equal(false)

      // update rewards second time
      const newTimestamp = BigNumber.from(newRewardsUpdate.updateTimestamp).add(1)
      newVaultReward = {
        reward: parseEther('4'),
        unlockedMevReward: parseEther('2'),
        vault: vault.address,
      }
      newRewardsUpdate = getKeeperRewardsUpdateData([newVaultReward], oracles, {
        nonce: 2,
        updateTimestamp: newTimestamp.toString(),
      })
      await increaseTime(REWARDS_DELAY)
      await keeper.connect(oracle).updateRewards({
        rewardsRoot: newRewardsUpdate.root,
        rewardsIpfsHash: newRewardsUpdate.ipfsHash,
        updateTimestamp: newRewardsUpdate.updateTimestamp,
        avgRewardPerSecond: newRewardsUpdate.avgRewardPerSecond,

        signatures: getSignatures(newRewardsUpdate.signingData),
      })

      expect(await keeper.isCollateralized(vault.address)).to.equal(true)
      expect(await keeper.canHarvest(vault.address)).to.equal(true)
      expect(await keeper.isHarvestRequired(vault.address)).to.equal(true)
    })
  })

  describe('harvest (own escrow)', () => {
    let harvestParams: IKeeperRewards.HarvestParamsStruct
    let ownMevVault: EthVault

    beforeEach(async () => {
      ownMevVault = await createVault(
        admin,
        {
          capacity,
          feePercent,
          name,
          symbol,
          metadataIpfsHash,
        },
        true
      )
      const vaultReward = {
        reward: parseEther('5'),
        unlockedMevReward: 0,
        vault: ownMevVault.address,
      }
      const vaultRewards = [vaultReward]
      for (let i = 1; i < 11; i++) {
        const vlt = await createVault(
          admin,
          {
            capacity,
            feePercent,
            name,
            symbol,
            metadataIpfsHash,
          },
          true
        )
        vaultRewards.push({
          reward: parseEther(i.toString()),
          unlockedMevReward: 0,
          vault: vlt.address,
        })
      }

      const rewardsUpdate = getKeeperRewardsUpdateData(vaultRewards, oracles)
      await keeper.connect(oracle).updateRewards({
        rewardsRoot: rewardsUpdate.root,
        updateTimestamp: rewardsUpdate.updateTimestamp,
        rewardsIpfsHash: rewardsUpdate.ipfsHash,
        avgRewardPerSecond: rewardsUpdate.avgRewardPerSecond,
        signatures: getSignatures(rewardsUpdate.signingData),
      })
      harvestParams = {
        rewardsRoot: rewardsUpdate.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof: getRewardsRootProof(rewardsUpdate.tree, vaultReward),
      }
    })

    it('only vault can harvest', async () => {
      await expect(keeper.harvest(harvestParams)).to.be.revertedWith('AccessDenied')
    })

    it('fails for invalid reward', async () => {
      await expect(ownMevVault.updateState({ ...harvestParams, reward: 0 })).to.be.revertedWith(
        'InvalidProof'
      )
    })

    it('fails for invalid proof', async () => {
      await expect(ownMevVault.updateState({ ...harvestParams, proof: [] })).to.be.revertedWith(
        'InvalidProof'
      )
    })

    it('fails for invalid root', async () => {
      const invalidRoot = '0x' + '1'.repeat(64)
      await expect(
        ownMevVault.updateState({ ...harvestParams, rewardsRoot: invalidRoot })
      ).to.be.revertedWith('InvalidRewardsRoot')
    })

    it('ignores unlocked mev reward', async () => {
      const sharedMevEscrowBalance = parseEther('1')
      await setBalance(await sharedMevEscrow.address, sharedMevEscrowBalance)
      await increaseTime(REWARDS_DELAY)

      // update rewards root
      const vaultReward = {
        reward: parseEther('10'),
        vault: ownMevVault.address,
        unlockedMevReward: sharedMevEscrowBalance,
      }
      const rewardsUpdate = getKeeperRewardsUpdateData([vaultReward], oracles, {
        nonce: 2,
        updateTimestamp: '1680255895',
      })
      await keeper.connect(oracle).updateRewards({
        rewardsRoot: rewardsUpdate.root,
        updateTimestamp: rewardsUpdate.updateTimestamp,
        rewardsIpfsHash: rewardsUpdate.ipfsHash,
        avgRewardPerSecond: rewardsUpdate.avgRewardPerSecond,
        signatures: getSignatures(rewardsUpdate.signingData),
      })
      const harvestParams = {
        rewardsRoot: rewardsUpdate.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof: getRewardsRootProof(rewardsUpdate.tree, vaultReward),
      }

      const receipt = await ownMevVault.updateState(harvestParams)
      await expect(receipt)
        .to.emit(keeper, 'Harvested')
        .withArgs(ownMevVault.address, harvestParams.rewardsRoot, harvestParams.reward, 0)
      expect(await waffle.provider.getBalance(sharedMevEscrow.address)).to.equal(
        sharedMevEscrowBalance
      )
    })

    it('succeeds for latest rewards root', async () => {
      let receipt = await ownMevVault.updateState(harvestParams)
      await expect(receipt)
        .to.emit(keeper, 'Harvested')
        .withArgs(
          ownMevVault.address,
          harvestParams.rewardsRoot,
          harvestParams.reward,
          harvestParams.unlockedMevReward
        )

      let rewards = await keeper.rewards(ownMevVault.address)
      expect(rewards.nonce).to.equal(2)
      expect(rewards.assets).to.equal(harvestParams.reward)

      let unlockedMevRewards = await keeper.unlockedMevRewards(ownMevVault.address)
      expect(unlockedMevRewards.nonce).to.equal(0)
      expect(unlockedMevRewards.assets).to.equal(0)

      expect(await keeper.isCollateralized(ownMevVault.address)).to.equal(true)
      expect(await keeper.canHarvest(ownMevVault.address)).to.equal(false)
      expect(await keeper.isHarvestRequired(ownMevVault.address)).to.equal(false)
      await snapshotGasCost(receipt)

      // doesn't fail for harvesting twice
      receipt = await ownMevVault.updateState(harvestParams)
      await expect(receipt).to.not.emit(keeper, 'Harvested')

      rewards = await keeper.rewards(ownMevVault.address)
      expect(rewards.nonce).to.equal(2)
      expect(rewards.assets).to.equal(harvestParams.reward)

      unlockedMevRewards = await keeper.unlockedMevRewards(ownMevVault.address)
      expect(unlockedMevRewards.nonce).to.equal(0)
      expect(unlockedMevRewards.assets).to.equal(0)

      expect(await keeper.isCollateralized(ownMevVault.address)).to.equal(true)
      expect(await keeper.canHarvest(ownMevVault.address)).to.equal(false)
      expect(await keeper.isHarvestRequired(ownMevVault.address)).to.equal(false)
      await snapshotGasCost(receipt)
    })

    it('succeeds for previous rewards root', async () => {
      const prevHarvestParams = harvestParams
      await increaseTime(REWARDS_DELAY)

      // update rewards root
      const vaultReward = {
        reward: parseEther('10'),
        vault: ownMevVault.address,
        unlockedMevReward: 0,
      }
      const rewardsUpdate = getKeeperRewardsUpdateData([vaultReward], oracles, {
        nonce: 2,
        updateTimestamp: '1680255895',
      })
      await keeper.connect(oracle).updateRewards({
        rewardsRoot: rewardsUpdate.root,
        updateTimestamp: rewardsUpdate.updateTimestamp,
        rewardsIpfsHash: rewardsUpdate.ipfsHash,
        avgRewardPerSecond: rewardsUpdate.avgRewardPerSecond,
        signatures: getSignatures(rewardsUpdate.signingData),
      })
      const currHarvestParams = {
        rewardsRoot: rewardsUpdate.root,
        reward: vaultReward.reward,
        unlockedMevReward: 0,
        proof: getRewardsRootProof(rewardsUpdate.tree, vaultReward),
      }

      let receipt = await ownMevVault.updateState(prevHarvestParams)
      await expect(receipt)
        .to.emit(keeper, 'Harvested')
        .withArgs(ownMevVault.address, prevHarvestParams.rewardsRoot, prevHarvestParams.reward, 0)

      let rewards = await keeper.rewards(ownMevVault.address)
      expect(rewards.nonce).to.equal(2)
      expect(rewards.assets).to.equal(prevHarvestParams.reward)

      expect(await keeper.isCollateralized(ownMevVault.address)).to.equal(true)
      expect(await keeper.canHarvest(ownMevVault.address)).to.equal(true)
      expect(await keeper.isHarvestRequired(ownMevVault.address)).to.equal(false)
      await snapshotGasCost(receipt)

      receipt = await ownMevVault.updateState(currHarvestParams)
      await expect(receipt)
        .to.emit(keeper, 'Harvested')
        .withArgs(
          ownMevVault.address,
          currHarvestParams.rewardsRoot,
          currHarvestParams.reward.sub(prevHarvestParams.reward),
          0
        )

      rewards = await keeper.rewards(ownMevVault.address)
      expect(rewards.nonce).to.equal(3)
      expect(rewards.assets).to.equal(currHarvestParams.reward)

      expect(await keeper.isCollateralized(ownMevVault.address)).to.equal(true)
      expect(await keeper.canHarvest(ownMevVault.address)).to.equal(false)
      expect(await keeper.isHarvestRequired(ownMevVault.address)).to.equal(false)
      await snapshotGasCost(receipt)

      // doesn't fail for harvesting previous again
      receipt = await ownMevVault.updateState(prevHarvestParams)
      await expect(receipt).to.not.emit(keeper, 'Harvested')

      rewards = await keeper.rewards(ownMevVault.address)
      expect(rewards.nonce).to.equal(3)
      expect(rewards.assets).to.equal(currHarvestParams.reward)

      expect(await keeper.isCollateralized(ownMevVault.address)).to.equal(true)
      expect(await keeper.canHarvest(ownMevVault.address)).to.equal(false)
      expect(await keeper.isHarvestRequired(ownMevVault.address)).to.equal(false)
      await snapshotGasCost(receipt)
    })
  })

  describe('harvest (shared escrow)', () => {
    let harvestParams: IKeeperRewards.HarvestParamsStruct
    let sharedMevVault: EthVault

    beforeEach(async () => {
      sharedMevVault = await createVault(
        admin,
        {
          capacity,
          feePercent,
          name,
          symbol,
          metadataIpfsHash,
        },
        false
      )
      const vaultReward = {
        reward: parseEther('5'),
        unlockedMevReward: parseEther('2'),
        vault: sharedMevVault.address,
      }
      const vaultRewards = [vaultReward]
      for (let i = 1; i < 11; i++) {
        const vlt = await createVault(
          admin,
          {
            capacity,
            feePercent,
            name,
            symbol,
            metadataIpfsHash,
          },
          true
        )
        const amount = parseEther(i.toString())
        vaultRewards.push({
          reward: amount,
          unlockedMevReward: amount,
          vault: vlt.address,
        })
      }

      const rewardsUpdate = getKeeperRewardsUpdateData(vaultRewards, oracles)
      await keeper.connect(oracle).updateRewards({
        rewardsRoot: rewardsUpdate.root,
        updateTimestamp: rewardsUpdate.updateTimestamp,
        rewardsIpfsHash: rewardsUpdate.ipfsHash,
        avgRewardPerSecond: rewardsUpdate.avgRewardPerSecond,
        signatures: getSignatures(rewardsUpdate.signingData),
      })
      harvestParams = {
        rewardsRoot: rewardsUpdate.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof: getRewardsRootProof(rewardsUpdate.tree, vaultReward),
      }
      await setBalance(sharedMevEscrow.address, BigNumber.from(harvestParams.unlockedMevReward))
    })

    it('only vault can harvest', async () => {
      await expect(keeper.harvest(harvestParams)).to.be.revertedWith('AccessDenied')
    })

    it('fails for invalid unlocked MEV reward', async () => {
      await expect(
        sharedMevVault.updateState({ ...harvestParams, unlockedMevReward: 0 })
      ).to.be.revertedWith('InvalidProof')
    })

    it('fails for invalid proof', async () => {
      await expect(sharedMevVault.updateState({ ...harvestParams, proof: [] })).to.be.revertedWith(
        'InvalidProof'
      )
    })

    it('fails for invalid root', async () => {
      const invalidRoot = '0x' + '1'.repeat(64)
      await expect(
        sharedMevVault.updateState({ ...harvestParams, rewardsRoot: invalidRoot })
      ).to.be.revertedWith('InvalidRewardsRoot')
    })

    it('succeeds for latest rewards root', async () => {
      let receipt = await sharedMevVault.updateState(harvestParams)
      await expect(receipt)
        .to.emit(keeper, 'Harvested')
        .withArgs(
          sharedMevVault.address,
          harvestParams.rewardsRoot,
          harvestParams.reward,
          harvestParams.unlockedMevReward
        )
      expect(await waffle.provider.getBalance(sharedMevEscrow.address)).to.equal(0)
      await expect(receipt)
        .to.emit(sharedMevEscrow, 'Harvested')
        .withArgs(sharedMevVault.address, harvestParams.unlockedMevReward)

      let rewards = await keeper.rewards(sharedMevVault.address)
      expect(rewards.nonce).to.equal(2)
      expect(rewards.assets).to.equal(harvestParams.reward)

      let unlockedMevRewards = await keeper.unlockedMevRewards(sharedMevVault.address)
      expect(unlockedMevRewards.nonce).to.equal(2)
      expect(unlockedMevRewards.assets).to.equal(harvestParams.unlockedMevReward)

      expect(await keeper.isCollateralized(sharedMevVault.address)).to.equal(true)
      expect(await keeper.canHarvest(sharedMevVault.address)).to.equal(false)
      expect(await keeper.isHarvestRequired(sharedMevVault.address)).to.equal(false)
      await snapshotGasCost(receipt)

      // doesn't fail for harvesting twice
      receipt = await sharedMevVault.updateState(harvestParams)
      await expect(receipt).to.not.emit(keeper, 'Harvested')
      await expect(receipt).to.not.emit(sharedMevEscrow, 'Harvested')

      rewards = await keeper.rewards(sharedMevVault.address)
      expect(rewards.nonce).to.equal(2)
      expect(rewards.assets).to.equal(harvestParams.reward)

      unlockedMevRewards = await keeper.unlockedMevRewards(sharedMevVault.address)
      expect(unlockedMevRewards.nonce).to.equal(2)
      expect(unlockedMevRewards.assets).to.equal(harvestParams.unlockedMevReward)

      expect(await keeper.isCollateralized(sharedMevVault.address)).to.equal(true)
      expect(await keeper.canHarvest(sharedMevVault.address)).to.equal(false)
      expect(await keeper.isHarvestRequired(sharedMevVault.address)).to.equal(false)
      await snapshotGasCost(receipt)
    })

    it('succeeds for previous rewards root', async () => {
      const prevHarvestParams = harvestParams
      await increaseTime(REWARDS_DELAY)

      // update rewards root
      const vaultReward = {
        reward: parseEther('10'),
        vault: sharedMevVault.address,
        unlockedMevReward: parseEther('4'),
      }
      await setBalance(sharedMevEscrow.address, vaultReward.unlockedMevReward)
      const rewardsUpdate = getKeeperRewardsUpdateData([vaultReward], oracles, {
        nonce: 2,
        updateTimestamp: '1680255895',
      })
      await keeper.connect(oracle).updateRewards({
        rewardsRoot: rewardsUpdate.root,
        updateTimestamp: rewardsUpdate.updateTimestamp,
        rewardsIpfsHash: rewardsUpdate.ipfsHash,
        avgRewardPerSecond: rewardsUpdate.avgRewardPerSecond,
        signatures: getSignatures(rewardsUpdate.signingData),
      })
      const currHarvestParams = {
        rewardsRoot: rewardsUpdate.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof: getRewardsRootProof(rewardsUpdate.tree, vaultReward),
      }

      let receipt = await sharedMevVault.updateState(prevHarvestParams)
      await expect(receipt)
        .to.emit(keeper, 'Harvested')
        .withArgs(
          sharedMevVault.address,
          prevHarvestParams.rewardsRoot,
          prevHarvestParams.reward,
          prevHarvestParams.unlockedMevReward
        )
      expect(await waffle.provider.getBalance(sharedMevEscrow.address)).to.equal(parseEther('2'))
      await expect(receipt)
        .to.emit(sharedMevEscrow, 'Harvested')
        .withArgs(sharedMevVault.address, prevHarvestParams.unlockedMevReward)

      let rewards = await keeper.rewards(sharedMevVault.address)
      expect(rewards.nonce).to.equal(2)
      expect(rewards.assets).to.equal(prevHarvestParams.reward)

      expect(await keeper.isCollateralized(sharedMevVault.address)).to.equal(true)
      expect(await keeper.canHarvest(sharedMevVault.address)).to.equal(true)
      expect(await keeper.isHarvestRequired(sharedMevVault.address)).to.equal(false)
      await snapshotGasCost(receipt)

      receipt = await sharedMevVault.updateState(currHarvestParams)
      const sharedMevDelta = currHarvestParams.unlockedMevReward.sub(
        prevHarvestParams.unlockedMevReward
      )
      await expect(receipt)
        .to.emit(keeper, 'Harvested')
        .withArgs(
          sharedMevVault.address,
          currHarvestParams.rewardsRoot,
          currHarvestParams.reward.sub(prevHarvestParams.reward),
          sharedMevDelta
        )
      await expect(receipt)
        .to.emit(sharedMevEscrow, 'Harvested')
        .withArgs(sharedMevVault.address, sharedMevDelta)
      expect(await waffle.provider.getBalance(sharedMevEscrow.address)).to.equal(0)

      rewards = await keeper.rewards(sharedMevVault.address)
      expect(rewards.nonce).to.equal(3)
      expect(rewards.assets).to.equal(currHarvestParams.reward)

      expect(await keeper.isCollateralized(sharedMevVault.address)).to.equal(true)
      expect(await keeper.canHarvest(sharedMevVault.address)).to.equal(false)
      expect(await keeper.isHarvestRequired(sharedMevVault.address)).to.equal(false)
      await snapshotGasCost(receipt)

      // doesn't fail for harvesting previous again
      receipt = await sharedMevVault.updateState(prevHarvestParams)
      await expect(receipt).to.not.emit(keeper, 'Harvested')
      await expect(receipt).to.not.emit(sharedMevEscrow, 'Harvested')
      expect(await waffle.provider.getBalance(sharedMevEscrow.address)).to.equal(0)

      rewards = await keeper.rewards(sharedMevVault.address)
      expect(rewards.nonce).to.equal(3)
      expect(rewards.assets).to.equal(currHarvestParams.reward)

      expect(await keeper.isCollateralized(sharedMevVault.address)).to.equal(true)
      expect(await keeper.canHarvest(sharedMevVault.address)).to.equal(false)
      expect(await keeper.isHarvestRequired(sharedMevVault.address)).to.equal(false)
      await snapshotGasCost(receipt)
    })
  })
})
