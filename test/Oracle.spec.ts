import { ethers, waffle } from 'hardhat'
import { BigNumber, Wallet } from 'ethers'
import { hexlify, parseEther } from 'ethers/lib/utils'
import { EthVault, EthOracle, Signers } from '../typechain-types'
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

describe('Oracle', () => {
  const maxTotalAssets = parseEther('1000')
  const feePercent = 1000
  const vaultName = 'SW ETH Vault'
  const vaultSymbol = 'SW-ETH-1'
  const validatorsRoot = '0x059a8487a1ce461e9670c4646ef85164ae8791613866d28c972fb351dc45c606'
  const validatorsIpfsHash = '/ipfs/QmfPnyNojfyqoi9yqS3jMp16GGiTQee4bdCXJC64KqvTgc'

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createVault']
  let getSignatures: ThenArg<ReturnType<typeof ethVaultFixture>>['getSignatures']

  let sender: Wallet, owner: Wallet, operator: Wallet
  let oracle: EthOracle, signers: Signers, vault: EthVault

  before('create fixture loader', async () => {
    ;[sender, operator, owner] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([owner])
  })

  beforeEach(async () => {
    ;({ signers, oracle, createVault, getSignatures } = await loadFixture(ethVaultFixture))
    vault = await createVault(
      operator,
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
      rewardsRoot = createVaultRewardsRoot([vaultReward], signers)
    })

    it('fails with invalid root', async () => {
      await expect(
        oracle.setRewardsRoot(
          ZERO_BYTES32,
          rewardsRoot.ipfsHash,
          getSignatures(rewardsRoot.signingData)
        )
      ).to.be.revertedWith('InvalidRewardsRoot()')
    })

    it('fails with invalid IPFS hash', async () => {
      await expect(
        oracle.setRewardsRoot(
          rewardsRoot.root,
          ZERO_BYTES32,
          getSignatures(rewardsRoot.signingData)
        )
      ).to.be.revertedWith('InvalidSigner()')
    })

    it('fails with invalid nonce', async () => {
      const signatures = getSignatures(rewardsRoot.signingData)
      await oracle
        .connect(sender)
        .setRewardsRoot(rewardsRoot.root, rewardsRoot.ipfsHash, signatures)

      const newVaultReward = { reward: parseEther('3'), vault: vault.address }
      const newRewardsRoot = createVaultRewardsRoot([newVaultReward], signers)
      await expect(
        oracle.setRewardsRoot(
          newRewardsRoot.root,
          newRewardsRoot.ipfsHash,
          getSignatures(newRewardsRoot.signingData)
        )
      ).to.be.revertedWith('InvalidSigner()')
    })

    it('succeeds', async () => {
      const signatures = getSignatures(rewardsRoot.signingData)
      const receipt = await oracle
        .connect(sender)
        .setRewardsRoot(rewardsRoot.root, rewardsRoot.ipfsHash, signatures)

      await expect(receipt)
        .to.emit(oracle, 'RewardsRootUpdated')
        .withArgs(sender.address, rewardsRoot.root, 0, rewardsRoot.ipfsHash, hexlify(signatures))
      expect(await oracle.rewardsRoot()).to.eq(rewardsRoot.root)
      expect(await oracle.rewardsNonce()).to.eq(1)
      await snapshotGasCost(receipt)
    })
  })

  describe('is harvested', () => {
    let vaultReward: VaultReward
    let rewardsRoot: RewardsRoot
    let proof: string[]

    beforeEach(async () => {
      vaultReward = { reward: parseEther('5'), vault: vault.address }
      rewardsRoot = createVaultRewardsRoot([vaultReward], signers)
      const signatures = getSignatures(rewardsRoot.signingData)
      await oracle.setRewardsRoot(rewardsRoot.root, rewardsRoot.ipfsHash, signatures)
      proof = getRewardsRootProof(rewardsRoot.tree, vaultReward)
    })

    it('returns true for uncollateralized vault', async () => {
      expect(await oracle.isHarvested(vault.address)).to.equal(true)
    })

    it('returns false for collateralized unharvested vault', async () => {
      await oracle.harvest(vaultReward.vault, vaultReward.reward, proof)
      const newVaultReward = { reward: parseEther('3'), vault: vault.address }
      const newRewardsRoot = createVaultRewardsRoot([newVaultReward], signers, 1)
      await oracle.setRewardsRoot(
        newRewardsRoot.root,
        newRewardsRoot.ipfsHash,
        getSignatures(newRewardsRoot.signingData)
      )
      expect(await oracle.isHarvested(vault.address)).to.equal(false)
    })

    it('returns true for collateralized harvested vault', async () => {
      await oracle.harvest(vaultReward.vault, vaultReward.reward, proof)
      const newVaultReward = { reward: parseEther('3'), vault: vault.address }
      const newRewardsRoot = createVaultRewardsRoot([newVaultReward], signers, 1)
      await oracle.setRewardsRoot(
        newRewardsRoot.root,
        newRewardsRoot.ipfsHash,
        getSignatures(newRewardsRoot.signingData)
      )
      await oracle.harvest(
        newVaultReward.vault,
        newVaultReward.reward,
        getRewardsRootProof(newRewardsRoot.tree, newVaultReward)
      )
      expect(await oracle.isHarvested(vault.address)).to.equal(true)
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
          operator,
          maxTotalAssets,
          validatorsRoot,
          feePercent,
          vaultName,
          vaultSymbol,
          validatorsIpfsHash
        )
        vaultRewards.push({ reward: parseEther(i.toString()), vault: vlt.address })
      }

      rewardsRoot = createVaultRewardsRoot(vaultRewards, signers)
      proof = getRewardsRootProof(rewardsRoot.tree, vaultReward)
      await oracle.setRewardsRoot(
        rewardsRoot.root,
        rewardsRoot.ipfsHash,
        getSignatures(rewardsRoot.signingData)
      )
    })

    it('fails for invalid vault', async () => {
      await expect(oracle.harvest(ZERO_ADDRESS, vaultReward.reward, proof)).to.be.revertedWith(
        'InvalidVault()'
      )
    })

    it('fails for invalid reward', async () => {
      await expect(oracle.harvest(vaultReward.vault, 0, proof)).to.be.revertedWith('InvalidProof()')
    })

    it('fails for invalid proof', async () => {
      await expect(oracle.harvest(vaultReward.vault, vaultReward.reward, [])).to.be.revertedWith(
        'InvalidProof()'
      )
    })

    it('calculates delta since last update', async () => {
      await oracle.harvest(vaultReward.vault, vaultReward.reward, proof)

      const newVaultReward = {
        reward: BigNumber.from(vaultReward.reward).sub(parseEther('1')),
        vault: vaultReward.vault,
      }

      const newRewardsRoot = createVaultRewardsRoot([newVaultReward], signers, 1)
      const signatures = getSignatures(newRewardsRoot.signingData)
      await oracle.setRewardsRoot(newRewardsRoot.root, newRewardsRoot.ipfsHash, signatures)

      const newProof = getRewardsRootProof(newRewardsRoot.tree, newVaultReward)
      const receipt = await oracle
        .connect(sender)
        .harvest(newVaultReward.vault, newVaultReward.reward, newProof)
      await expect(receipt)
        .to.emit(oracle, 'Harvested')
        .withArgs(sender.address, newVaultReward.vault, newVaultReward.reward)
      await expect(receipt)
        .to.emit(vault, 'StateUpdated')
        .withArgs(BigNumber.from(newVaultReward.reward).sub(vaultReward.reward))
      await snapshotGasCost(receipt)
    })

    it('succeeds for already harvested vault', async () => {
      await oracle.harvest(vaultReward.vault, vaultReward.reward, proof)
      const receipt = await oracle
        .connect(sender)
        .harvest(vaultReward.vault, vaultReward.reward, proof)
      await expect(receipt)
        .to.emit(oracle, 'Harvested')
        .withArgs(sender.address, vaultReward.vault, vaultReward.reward)
      await expect(receipt).to.emit(vault, 'StateUpdated').withArgs(0)
      await snapshotGasCost(receipt)
    })

    it('succeeds for not harvested vault', async () => {
      const receipt = oracle.connect(sender).harvest(vaultReward.vault, vaultReward.reward, proof)
      await expect(receipt)
        .to.emit(oracle, 'Harvested')
        .withArgs(sender.address, vaultReward.vault, vaultReward.reward)
      await expect(receipt).to.emit(vault, 'StateUpdated').withArgs(vaultReward.reward)
      await snapshotGasCost(receipt)
    })
  })

  describe('upgrade', () => {
    it('fails for not an owner', async () => {
      await expect(oracle.connect(sender).upgradeTo(oracle.address)).to.revertedWith(
        'Ownable: caller is not the owner'
      )
    })
    it('succeeds for owner', async () => {
      await expect(oracle.connect(owner).upgradeTo(oracle.address)).to.revertedWith(
        'ERC1967Upgrade: new implementation is not UUPS'
      )
    })
  })
})
