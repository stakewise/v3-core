import { ethers, waffle } from 'hardhat'
import { BigNumber, Wallet } from 'ethers'
import { hexlify, parseEther } from 'ethers/lib/utils'
import { EthVault, EthKeeper, Oracles } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { ZERO_ADDRESS, ZERO_BYTES32 } from './shared/constants'
import snapshotGasCost from './shared/snapshotGasCost'
import {
  createVaultRewardsRoot,
  getRewardsRootProof,
  RewardsRoot,
  VaultReward,
} from './shared/rewards'

const createFixtureLoader = waffle.createFixtureLoader

describe('BaseKeeper', () => {
  const maxTotalAssets = parseEther('1000')
  const feePercent = 1000
  const vaultName = 'SW ETH Vault'
  const vaultSymbol = 'SW-ETH-1'
  const validatorsRoot = '0x059a8487a1ce461e9670c4646ef85164ae8791613866d28c972fb351dc45c606'
  const validatorsIpfsHash = '/ipfs/QmfPnyNojfyqoi9yqS3jMp16GGiTQee4bdCXJC64KqvTgc'

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createVault']
  let getSignatures: ThenArg<ReturnType<typeof ethVaultFixture>>['getSignatures']

  let sender: Wallet, owner: Wallet, admin: Wallet
  let keeper: EthKeeper, oracles: Oracles, vault: EthVault

  before('create fixture loader', async () => {
    ;[sender, admin, owner] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([owner])
  })

  beforeEach(async () => {
    ;({ oracles, keeper, createVault, getSignatures } = await loadFixture(ethVaultFixture))
    vault = await createVault(
      admin,
      maxTotalAssets,
      validatorsRoot,
      feePercent,
      vaultName,
      vaultSymbol,
      validatorsIpfsHash
    )
  })

  describe('set rewards root', () => {
    let vaultReward: VaultReward
    let rewardsRoot: RewardsRoot

    beforeEach(async () => {
      vaultReward = { reward: parseEther('5'), vault: vault.address }
      rewardsRoot = createVaultRewardsRoot([vaultReward], oracles)
    })

    it('fails with invalid root', async () => {
      await expect(
        keeper.setRewardsRoot(
          ZERO_BYTES32,
          rewardsRoot.updateTimestamp,
          rewardsRoot.ipfsHash,
          getSignatures(rewardsRoot.signingData)
        )
      ).to.be.revertedWith('InvalidRewardsRoot()')
    })

    it('fails with invalid IPFS hash', async () => {
      await expect(
        keeper.setRewardsRoot(
          rewardsRoot.root,
          rewardsRoot.updateTimestamp,
          ZERO_BYTES32,
          getSignatures(rewardsRoot.signingData)
        )
      ).to.be.revertedWith('InvalidOracle()')
    })

    it('fails with invalid nonce', async () => {
      const signatures = getSignatures(rewardsRoot.signingData)
      await keeper
        .connect(sender)
        .setRewardsRoot(
          rewardsRoot.root,
          rewardsRoot.updateTimestamp,
          rewardsRoot.ipfsHash,
          signatures
        )

      const newVaultReward = { reward: parseEther('3'), vault: vault.address }
      const newRewardsRoot = createVaultRewardsRoot([newVaultReward], oracles)
      await expect(
        keeper.setRewardsRoot(
          newRewardsRoot.root,
          rewardsRoot.updateTimestamp,
          newRewardsRoot.ipfsHash,
          getSignatures(newRewardsRoot.signingData)
        )
      ).to.be.revertedWith('InvalidOracle()')
    })

    it('succeeds', async () => {
      const signatures = getSignatures(rewardsRoot.signingData)
      const receipt = await keeper
        .connect(sender)
        .setRewardsRoot(
          rewardsRoot.root,
          rewardsRoot.updateTimestamp,
          rewardsRoot.ipfsHash,
          signatures
        )

      await expect(receipt)
        .to.emit(keeper, 'RewardsRootUpdated')
        .withArgs(
          sender.address,
          rewardsRoot.root,
          rewardsRoot.updateTimestamp,
          1,
          rewardsRoot.ipfsHash,
          hexlify(signatures)
        )
      expect(await keeper.rewardsRoot()).to.eq(rewardsRoot.root)
      expect(await keeper.rewardsNonce()).to.eq(2)
      await snapshotGasCost(receipt)
    })
  })

  describe('is harvested', () => {
    let vaultReward: VaultReward
    let rewardsRoot: RewardsRoot
    let proof: string[]

    beforeEach(async () => {
      vaultReward = { reward: parseEther('5'), vault: vault.address }
      rewardsRoot = createVaultRewardsRoot([vaultReward], oracles)
      const signatures = getSignatures(rewardsRoot.signingData)
      await keeper.setRewardsRoot(
        rewardsRoot.root,
        rewardsRoot.updateTimestamp,
        rewardsRoot.ipfsHash,
        signatures
      )
      proof = getRewardsRootProof(rewardsRoot.tree, vaultReward)
    })

    it('returns true for uncollateralized vault', async () => {
      expect(await keeper.isHarvested(vault.address)).to.equal(true)
    })

    it('returns false for collateralized unharvested vault', async () => {
      await keeper.harvest(vaultReward.vault, vaultReward.reward, proof)
      let newVaultReward = { reward: parseEther('3'), vault: vault.address }
      let newRewardsRoot = createVaultRewardsRoot(
        [newVaultReward],
        oracles,
        rewardsRoot.updateTimestamp,
        2
      )
      await keeper.setRewardsRoot(
        newRewardsRoot.root,
        rewardsRoot.updateTimestamp,
        newRewardsRoot.ipfsHash,
        getSignatures(newRewardsRoot.signingData)
      )

      // returns true if not harvested one time
      expect(await keeper.isHarvested(vault.address)).to.equal(true)

      const newTimestamp = rewardsRoot.updateTimestamp + 1
      newVaultReward = { reward: parseEther('4'), vault: vault.address }
      newRewardsRoot = createVaultRewardsRoot([newVaultReward], oracles, newTimestamp, 3)
      await keeper.setRewardsRoot(
        newRewardsRoot.root,
        newTimestamp,
        newRewardsRoot.ipfsHash,
        getSignatures(newRewardsRoot.signingData)
      )

      // returns false if not harvested two times
      expect(await keeper.isHarvested(vault.address)).to.equal(false)
    })

    it('returns true for collateralized harvested vault', async () => {
      await keeper.harvest(vaultReward.vault, vaultReward.reward, proof)
      const newVaultReward = { reward: parseEther('3'), vault: vault.address }
      const newRewardsRoot = createVaultRewardsRoot(
        [newVaultReward],
        oracles,
        rewardsRoot.updateTimestamp,
        2
      )
      await keeper.setRewardsRoot(
        newRewardsRoot.root,
        rewardsRoot.updateTimestamp,
        newRewardsRoot.ipfsHash,
        getSignatures(newRewardsRoot.signingData)
      )
      await keeper.harvest(
        newVaultReward.vault,
        newVaultReward.reward,
        getRewardsRootProof(newRewardsRoot.tree, newVaultReward)
      )
      expect(await keeper.isHarvested(vault.address)).to.equal(true)
    })
  })

  describe('harvest', () => {
    let vaultReward: VaultReward
    let rewardsRoot: RewardsRoot
    let proof: string[]

    beforeEach(async () => {
      vaultReward = { reward: parseEther('5'), vault: vault.address }

      const vaultRewards = [vaultReward]
      for (let i = 1; i < 11; i++) {
        const vlt = await createVault(
          admin,
          maxTotalAssets,
          validatorsRoot,
          feePercent,
          vaultName,
          vaultSymbol,
          validatorsIpfsHash
        )
        vaultRewards.push({ reward: parseEther(i.toString()), vault: vlt.address })
      }

      rewardsRoot = createVaultRewardsRoot(vaultRewards, oracles)
      proof = getRewardsRootProof(rewardsRoot.tree, vaultReward)
      await keeper.setRewardsRoot(
        rewardsRoot.root,
        rewardsRoot.updateTimestamp,
        rewardsRoot.ipfsHash,
        getSignatures(rewardsRoot.signingData)
      )
    })

    it('fails for invalid vault', async () => {
      await expect(keeper.harvest(ZERO_ADDRESS, vaultReward.reward, proof)).to.be.revertedWith(
        'InvalidVault()'
      )
    })

    it('fails for invalid reward', async () => {
      await expect(keeper.harvest(vaultReward.vault, 0, proof)).to.be.revertedWith('InvalidProof()')
    })

    it('fails for invalid proof', async () => {
      await expect(keeper.harvest(vaultReward.vault, vaultReward.reward, [])).to.be.revertedWith(
        'InvalidProof()'
      )
    })

    it('calculates delta since last update', async () => {
      await keeper.harvest(vaultReward.vault, vaultReward.reward, proof)

      const newVaultReward = {
        reward: BigNumber.from(vaultReward.reward).sub(parseEther('1')),
        vault: vaultReward.vault,
      }

      const newRewardsRoot = createVaultRewardsRoot(
        [newVaultReward],
        oracles,
        rewardsRoot.updateTimestamp,
        2
      )
      const signatures = getSignatures(newRewardsRoot.signingData)
      await keeper.setRewardsRoot(
        newRewardsRoot.root,
        rewardsRoot.updateTimestamp,
        newRewardsRoot.ipfsHash,
        signatures
      )

      const newProof = getRewardsRootProof(newRewardsRoot.tree, newVaultReward)
      const receipt = await keeper
        .connect(sender)
        .harvest(newVaultReward.vault, newVaultReward.reward, newProof)
      await expect(receipt)
        .to.emit(keeper, 'Harvested')
        .withArgs(sender.address, newVaultReward.vault, newVaultReward.reward)
      await expect(receipt)
        .to.emit(vault, 'StateUpdated')
        .withArgs(BigNumber.from(newVaultReward.reward).sub(vaultReward.reward))
      await snapshotGasCost(receipt)
    })

    it('succeeds for already harvested vault', async () => {
      await keeper.harvest(vaultReward.vault, vaultReward.reward, proof)
      const receipt = await keeper
        .connect(sender)
        .harvest(vaultReward.vault, vaultReward.reward, proof)
      await expect(receipt).to.not.emit(keeper, 'Harvested')
      await expect(receipt).to.emit(vault, 'StateUpdated').withArgs(0)
      await snapshotGasCost(receipt)
    })

    it('succeeds for not harvested vault', async () => {
      const receipt = keeper.connect(sender).harvest(vaultReward.vault, vaultReward.reward, proof)
      await expect(receipt)
        .to.emit(keeper, 'Harvested')
        .withArgs(sender.address, vaultReward.vault, vaultReward.reward)
      await expect(receipt).to.emit(vault, 'StateUpdated').withArgs(vaultReward.reward)
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
