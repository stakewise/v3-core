import { ethers, waffle } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import { EthVault, EthKeeper, Oracles } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import snapshotGasCost from './shared/snapshotGasCost'
import { ZERO_ADDRESS } from './shared/constants'
import { collateralizeEthVault, updateRewardsRoot } from './shared/rewards'

const createFixtureLoader = waffle.createFixtureLoader

describe('EthVault - settings', () => {
  const maxTotalAssets = parseEther('1000')
  const feePercent = 1000
  const vaultName = 'SW ETH Vault'
  const vaultSymbol = 'SW-ETH-1'
  const validatorsRoot = '0x059a8487a1ce461e9670c4646ef85164ae8791613866d28c972fb351dc45c606'
  const validatorsIpfsHash = '/ipfs/QmfPnyNojfyqoi9yqS3jMp16GGiTQee4bdCXJC64KqvTgc'

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createVault']
  let getSignatures: ThenArg<ReturnType<typeof ethVaultFixture>>['getSignatures']
  let admin: Wallet, owner: Wallet, other: Wallet, newFeeRecipient: Wallet
  let keeper: EthKeeper, oracles: Oracles, validatorsRegistry: Contract

  before('create fixture loader', async () => {
    ;[admin, owner, other, newFeeRecipient] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([owner])
  })

  beforeEach('deploy fixture', async () => {
    ;({ keeper, oracles, getSignatures, validatorsRegistry, createVault } = await loadFixture(
      ethVaultFixture
    ))
  })

  describe('fee percent', () => {
    it('cannot be set to invalid value', async () => {
      await expect(
        createVault(
          admin,
          maxTotalAssets,
          validatorsRoot,
          10001,
          vaultName,
          vaultSymbol,
          validatorsIpfsHash
        )
      ).to.be.revertedWith('InvalidFeePercent()')
    })
  })

  describe('validators root', () => {
    const newValidatorsRoot = '0x059a8487a1ce461e9670c4646ef85164ae8791613866d28c972fb351dc45c606'
    const newValidatorsIpfsHash = '/ipfs/QmfPnyNojfyqoi9yqS3jMp16GGiTQee4bdCXJC64KqvTgc'
    let vault: EthVault

    beforeEach('deploy vault', async () => {
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

    it('only admin can update', async () => {
      await expect(
        vault.connect(other).setValidatorsRoot(newValidatorsRoot, newValidatorsIpfsHash)
      ).to.be.revertedWith('AccessDenied()')
    })

    it('can update', async () => {
      const receipt = await vault
        .connect(admin)
        .setValidatorsRoot(newValidatorsRoot, newValidatorsIpfsHash)
      await expect(receipt)
        .to.emit(vault, 'ValidatorsRootUpdated')
        .withArgs(newValidatorsRoot, newValidatorsIpfsHash)
      expect(await vault.validatorsRoot()).to.be.eq(newValidatorsRoot)
      await snapshotGasCost(receipt)
    })
  })

  describe('fee recipient', () => {
    let vault: EthVault

    beforeEach('deploy vault', async () => {
      vault = await createVault(
        admin,
        maxTotalAssets,
        validatorsRoot,
        feePercent,
        vaultName,
        vaultSymbol,
        validatorsIpfsHash
      )
      await collateralizeEthVault(vault, oracles, keeper, validatorsRegistry, admin, getSignatures)
    })

    it('only admin can update', async () => {
      await expect(
        vault.connect(other).setFeeRecipient(newFeeRecipient.address)
      ).to.be.revertedWith('AccessDenied()')
    })

    it('cannot set to zero address', async () => {
      await expect(vault.connect(admin).setFeeRecipient(ZERO_ADDRESS)).to.be.revertedWith(
        'InvalidFeeRecipient()'
      )
    })

    it('cannot update when not harvested', async () => {
      await updateRewardsRoot(keeper, oracles, getSignatures, [{ vault: vault.address, reward: 1 }])
      await updateRewardsRoot(keeper, oracles, getSignatures, [{ vault: vault.address, reward: 2 }])
      await expect(
        vault.connect(admin).setFeeRecipient(newFeeRecipient.address)
      ).to.be.revertedWith('NotHarvested()')
    })

    it('can update', async () => {
      expect(await vault.feeRecipient()).to.be.eq(admin.address)
      const receipt = await vault.connect(admin).setFeeRecipient(newFeeRecipient.address)
      await expect(receipt).to.emit(vault, 'FeeRecipientUpdated').withArgs(newFeeRecipient.address)
      expect(await vault.feeRecipient()).to.be.eq(newFeeRecipient.address)
      await snapshotGasCost(receipt)
    })
  })
})
