import { ethers, waffle } from 'hardhat'
import { BigNumber, Wallet } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import { Keeper, EthVault, Oracles, IKeeperRewards } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { ORACLES, ZERO_BYTES32 } from './shared/constants'
import snapshotGasCost from './shared/snapshotGasCost'
import { createVaultRewardsRoot, getRewardsRootProof, VaultReward } from './shared/rewards'
import { setBalance } from './shared/utils'

const createFixtureLoader = waffle.createFixtureLoader

describe('KeeperRewards', () => {
  const capacity = parseEther('1000')
  const feePercent = 1000
  const name = 'SW ETH Vault'
  const symbol = 'SW-ETH-1'
  const validatorsRoot = '0x059a8487a1ce461e9670c4646ef85164ae8791613866d28c972fb351dc45c606'
  const validatorsIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7r'
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createVault']
  let getSignatures: ThenArg<ReturnType<typeof ethVaultFixture>>['getSignatures']

  let sender: Wallet, owner: Wallet, admin: Wallet, oracle: Wallet
  let keeper: Keeper, oracles: Oracles, vault: EthVault

  before('create fixture loader', async () => {
    ;[sender, admin, owner] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([owner])
    oracle = new Wallet(ORACLES[0], await waffle.provider)
  })

  beforeEach(async () => {
    ;({ oracles, keeper, createVault, getSignatures } = await loadFixture(ethVaultFixture))
    vault = await createVault(admin, {
      capacity,
      validatorsRoot,
      feePercent,
      name,
      symbol,
      validatorsIpfsHash,
      metadataIpfsHash,
    })
    await setBalance(oracle.address, parseEther('10000'))
  })

  describe('set rewards root', () => {
    let vaultReward: VaultReward
    let rewardsRootParams: IKeeperRewards.RewardsRootUpdateParamsStruct

    beforeEach(async () => {
      vaultReward = { reward: parseEther('5'), vault: vault.address }
      const rewardsRoot = createVaultRewardsRoot([vaultReward], oracles)
      rewardsRootParams = {
        rewardsRoot: rewardsRoot.root,
        updateTimestamp: rewardsRoot.updateTimestamp,
        rewardsIpfsHash: rewardsRoot.ipfsHash,
        signatures: getSignatures(rewardsRoot.signingData),
      }
    })

    it('fails with invalid root', async () => {
      await expect(
        keeper.connect(oracle).setRewardsRoot({ ...rewardsRootParams, rewardsRoot: ZERO_BYTES32 })
      ).to.be.revertedWith('InvalidRewardsRoot()')

      // check can't set to previous rewards root
      await keeper.connect(oracle).setRewardsRoot(rewardsRootParams)
      await expect(
        keeper.connect(oracle).setRewardsRoot({ ...rewardsRootParams, rewardsRoot: ZERO_BYTES32 })
      ).to.be.revertedWith('InvalidRewardsRoot()')
    })

    it('fails with invalid IPFS hash', async () => {
      await expect(
        keeper
          .connect(oracle)
          .setRewardsRoot({ ...rewardsRootParams, rewardsIpfsHash: ZERO_BYTES32 })
      ).to.be.revertedWith('InvalidOracle()')
    })

    it('fails with invalid nonce', async () => {
      await keeper.connect(oracle).setRewardsRoot(rewardsRootParams)
      const newVaultReward = { reward: parseEther('3'), vault: vault.address }
      const newRewardsRoot = createVaultRewardsRoot([newVaultReward], oracles)
      await expect(
        keeper.connect(oracle).setRewardsRoot({
          rewardsRoot: newRewardsRoot.root,
          rewardsIpfsHash: newRewardsRoot.ipfsHash,
          updateTimestamp: newRewardsRoot.updateTimestamp,
          signatures: getSignatures(newRewardsRoot.signingData),
        })
      ).to.be.revertedWith('InvalidOracle()')
    })

    it('succeeds', async () => {
      let receipt = await keeper.connect(oracle).setRewardsRoot(rewardsRootParams)
      await expect(receipt)
        .to.emit(keeper, 'RewardsRootUpdated')
        .withArgs(
          oracle.address,
          rewardsRootParams.rewardsRoot,
          rewardsRootParams.updateTimestamp,
          1,
          rewardsRootParams.rewardsIpfsHash
        )
      expect(await keeper.prevRewardsRoot()).to.eq(ZERO_BYTES32)
      expect(await keeper.rewardsRoot()).to.eq(rewardsRootParams.rewardsRoot)
      expect(await keeper.rewardsNonce()).to.eq(2)
      await snapshotGasCost(receipt)

      // check keeps previous rewards root
      const newVaultReward = { reward: parseEther('3'), vault: vault.address }
      const newRewardsRoot = createVaultRewardsRoot([newVaultReward], oracles, 1670256000, 2)
      receipt = await keeper.connect(oracle).setRewardsRoot({
        rewardsRoot: newRewardsRoot.root,
        rewardsIpfsHash: newRewardsRoot.ipfsHash,
        updateTimestamp: newRewardsRoot.updateTimestamp,
        signatures: getSignatures(newRewardsRoot.signingData),
      })
      await expect(receipt)
        .to.emit(keeper, 'RewardsRootUpdated')
        .withArgs(
          oracle.address,
          newRewardsRoot.root,
          newRewardsRoot.updateTimestamp,
          2,
          newRewardsRoot.ipfsHash
        )
      expect(await keeper.prevRewardsRoot()).to.eq(rewardsRootParams.rewardsRoot)
      expect(await keeper.rewardsRoot()).to.eq(newRewardsRoot.root)
      expect(await keeper.rewardsNonce()).to.eq(3)
      await snapshotGasCost(receipt)
    })
  })

  describe('is harvest required', () => {
    let harvestParams: IKeeperRewards.HarvestParamsStruct
    let proof: string[]

    beforeEach(async () => {
      const vaultReward = { reward: parseEther('5'), vault: vault.address }
      const rewardsRoot = createVaultRewardsRoot([vaultReward], oracles)
      await keeper.connect(oracle).setRewardsRoot({
        rewardsRoot: rewardsRoot.root,
        updateTimestamp: rewardsRoot.updateTimestamp,
        rewardsIpfsHash: rewardsRoot.ipfsHash,
        signatures: getSignatures(rewardsRoot.signingData),
      })
      proof = getRewardsRootProof(rewardsRoot.tree, vaultReward)
      harvestParams = {
        rewardsRoot: rewardsRoot.root,
        reward: vaultReward.reward,
        proof,
      }
    })

    it('returns false for uncollateralized vault', async () => {
      expect(await keeper.isCollateralized(vault.address)).to.equal(false)
      expect(await keeper.isHarvestRequired(vault.address)).to.equal(false)
      expect(await keeper.canHarvest(vault.address)).to.equal(false)
    })

    it('returns true for collateralized two times unharvested vault', async () => {
      // collateralize vault
      await vault.updateState(harvestParams)
      expect(await keeper.isCollateralized(vault.address)).to.equal(true)
      expect(await keeper.canHarvest(vault.address)).to.equal(false)
      expect(await keeper.isHarvestRequired(vault.address)).to.equal(false)

      // update rewards first time
      let newVaultReward = { reward: parseEther('3'), vault: vault.address }
      let newRewardsRoot = createVaultRewardsRoot([newVaultReward], oracles, 1670258895, 2)
      await keeper.connect(oracle).setRewardsRoot({
        rewardsRoot: newRewardsRoot.root,
        rewardsIpfsHash: newRewardsRoot.ipfsHash,
        updateTimestamp: newRewardsRoot.updateTimestamp,
        signatures: getSignatures(newRewardsRoot.signingData),
      })

      expect(await keeper.isCollateralized(vault.address)).to.equal(true)
      expect(await keeper.canHarvest(vault.address)).to.equal(true)
      expect(await keeper.isHarvestRequired(vault.address)).to.equal(false)

      // update rewards second time
      const newTimestamp = newRewardsRoot.updateTimestamp + 1
      newVaultReward = { reward: parseEther('4'), vault: vault.address }
      newRewardsRoot = createVaultRewardsRoot([newVaultReward], oracles, newTimestamp, 3)
      await keeper.connect(oracle).setRewardsRoot({
        rewardsRoot: newRewardsRoot.root,
        rewardsIpfsHash: newRewardsRoot.ipfsHash,
        updateTimestamp: newRewardsRoot.updateTimestamp,
        signatures: getSignatures(newRewardsRoot.signingData),
      })

      expect(await keeper.isCollateralized(vault.address)).to.equal(true)
      expect(await keeper.canHarvest(vault.address)).to.equal(true)
      expect(await keeper.isHarvestRequired(vault.address)).to.equal(true)
    })
  })

  describe('harvest', () => {
    let harvestParams: IKeeperRewards.HarvestParamsStruct
    let proof: string[]

    beforeEach(async () => {
      const vaultReward = { reward: parseEther('5'), vault: vault.address }
      const vaultRewards = [vaultReward]
      for (let i = 1; i < 11; i++) {
        const vlt = await createVault(admin, {
          capacity,
          validatorsRoot,
          feePercent,
          name,
          symbol,
          validatorsIpfsHash,
          metadataIpfsHash,
        })
        vaultRewards.push({ reward: parseEther(i.toString()), vault: vlt.address })
      }

      const rewardsRoot = createVaultRewardsRoot(vaultRewards, oracles)
      proof = getRewardsRootProof(rewardsRoot.tree, vaultReward)
      await keeper.connect(oracle).setRewardsRoot({
        rewardsRoot: rewardsRoot.root,
        updateTimestamp: rewardsRoot.updateTimestamp,
        rewardsIpfsHash: rewardsRoot.ipfsHash,
        signatures: getSignatures(rewardsRoot.signingData),
      })
      harvestParams = {
        rewardsRoot: rewardsRoot.root,
        reward: vaultReward.reward,
        proof,
      }
    })

    it('only vault can harvest', async () => {
      await expect(keeper.harvest(harvestParams)).to.be.revertedWith('AccessDenied()')
    })

    it('fails for invalid reward', async () => {
      await expect(vault.updateState({ ...harvestParams, reward: 0 })).to.be.revertedWith(
        'InvalidProof()'
      )
    })

    it('fails for invalid proof', async () => {
      await expect(vault.updateState({ ...harvestParams, proof: [] })).to.be.revertedWith(
        'InvalidProof()'
      )
    })

    it('fails for invalid root', async () => {
      const invalidRoot = '0x' + '1'.repeat(64)
      await expect(
        vault.updateState({ ...harvestParams, rewardsRoot: invalidRoot })
      ).to.be.revertedWith('InvalidRewardsRoot()')
    })

    it('succeeds for latest rewards root', async () => {
      let receipt = await vault.updateState(harvestParams)
      await expect(receipt)
        .to.emit(keeper, 'Harvested')
        .withArgs(vault.address, harvestParams.rewardsRoot, harvestParams.reward)
      await expect(receipt).to.emit(vault, 'StateUpdated').withArgs(harvestParams.reward)

      let rewardsSync = await keeper.rewards(vault.address)
      expect(rewardsSync.nonce).to.equal(2)
      expect(rewardsSync.reward).to.equal(harvestParams.reward)

      expect(await keeper.isCollateralized(vault.address)).to.equal(true)
      expect(await keeper.canHarvest(vault.address)).to.equal(false)
      expect(await keeper.isHarvestRequired(vault.address)).to.equal(false)
      await snapshotGasCost(receipt)

      // doesn't fail for harvesting twice
      receipt = await vault.updateState(harvestParams)
      await expect(receipt).to.not.emit(keeper, 'Harvested')
      await expect(receipt).to.not.emit(vault, 'StateUpdated')

      rewardsSync = await keeper.rewards(vault.address)
      expect(rewardsSync.nonce).to.equal(2)
      expect(rewardsSync.reward).to.equal(harvestParams.reward)

      expect(await keeper.isCollateralized(vault.address)).to.equal(true)
      expect(await keeper.canHarvest(vault.address)).to.equal(false)
      expect(await keeper.isHarvestRequired(vault.address)).to.equal(false)
      await snapshotGasCost(receipt)
    })

    it('succeeds for previous rewards root', async () => {
      const prevHarvestParams = harvestParams

      // update rewards root
      const vaultReward = { reward: parseEther('10'), vault: vault.address }
      const rewardsRoot = createVaultRewardsRoot([vaultReward], oracles, 1670255995, 2)
      await keeper.connect(oracle).setRewardsRoot({
        rewardsRoot: rewardsRoot.root,
        updateTimestamp: rewardsRoot.updateTimestamp,
        rewardsIpfsHash: rewardsRoot.ipfsHash,
        signatures: getSignatures(rewardsRoot.signingData),
      })
      proof = getRewardsRootProof(rewardsRoot.tree, vaultReward)
      const currHarvestParams = {
        rewardsRoot: rewardsRoot.root,
        reward: vaultReward.reward,
        proof,
      }

      let receipt = await vault.updateState(prevHarvestParams)
      await expect(receipt)
        .to.emit(keeper, 'Harvested')
        .withArgs(vault.address, prevHarvestParams.rewardsRoot, prevHarvestParams.reward)
      await expect(receipt).to.emit(vault, 'StateUpdated').withArgs(prevHarvestParams.reward)

      let rewardsSync = await keeper.rewards(vault.address)
      expect(rewardsSync.nonce).to.equal(2)
      expect(rewardsSync.reward).to.equal(prevHarvestParams.reward)

      expect(await keeper.isCollateralized(vault.address)).to.equal(true)
      expect(await keeper.canHarvest(vault.address)).to.equal(true)
      expect(await keeper.isHarvestRequired(vault.address)).to.equal(false)
      await snapshotGasCost(receipt)

      receipt = await vault.updateState(currHarvestParams)
      await expect(receipt)
        .to.emit(keeper, 'Harvested')
        .withArgs(vault.address, currHarvestParams.rewardsRoot, currHarvestParams.reward)
      await expect(receipt)
        .to.emit(vault, 'StateUpdated')
        .withArgs(currHarvestParams.reward.sub(BigNumber.from(prevHarvestParams.reward)))

      rewardsSync = await keeper.rewards(vault.address)
      expect(rewardsSync.nonce).to.equal(3)
      expect(rewardsSync.reward).to.equal(currHarvestParams.reward)

      expect(await keeper.isCollateralized(vault.address)).to.equal(true)
      expect(await keeper.canHarvest(vault.address)).to.equal(false)
      expect(await keeper.isHarvestRequired(vault.address)).to.equal(false)
      await snapshotGasCost(receipt)

      // doesn't fail for harvesting previous again
      receipt = await vault.updateState(prevHarvestParams)
      await expect(receipt).to.not.emit(keeper, 'Harvested')
      await expect(receipt).to.not.emit(vault, 'StateUpdated')

      rewardsSync = await keeper.rewards(vault.address)
      expect(rewardsSync.nonce).to.equal(3)
      expect(rewardsSync.reward).to.equal(currHarvestParams.reward)

      expect(await keeper.isCollateralized(vault.address)).to.equal(true)
      expect(await keeper.canHarvest(vault.address)).to.equal(false)
      expect(await keeper.isHarvestRequired(vault.address)).to.equal(false)
      await snapshotGasCost(receipt)
    })
  })

  describe('upgrade', () => {
    it('fails for not an owner', async () => {
      await expect(keeper.connect(sender).upgradeTo(keeper.address)).to.revertedWith(
        'Ownable: caller is not the owner'
      )
    })
    it('succeeds for owner', async () => {
      await expect(keeper.connect(owner).upgradeTo(keeper.address)).to.revertedWith(
        'ERC1967Upgrade: new implementation is not UUPS'
      )
    })
  })
})
