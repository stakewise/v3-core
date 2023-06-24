import { ethers, waffle } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import { Keeper, EthVault } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import snapshotGasCost from './shared/snapshotGasCost'
import { ZERO_ADDRESS } from './shared/constants'
import { collateralizeEthVault, updateRewards } from './shared/rewards'

const createFixtureLoader = waffle.createFixtureLoader

describe('EthVault - settings', () => {
  const capacity = parseEther('1000')
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVault']
  let admin: Wallet, owner: Wallet, keysManager: Wallet, other: Wallet, newFeeRecipient: Wallet
  let keeper: Keeper, validatorsRegistry: Contract

  before('create fixture loader', async () => {
    ;[admin, owner, keysManager, other, newFeeRecipient] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([owner])
  })

  beforeEach('deploy fixture', async () => {
    ;({
      keeper,
      validatorsRegistry,
      createEthVault: createVault,
    } = await loadFixture(ethVaultFixture))
  })

  describe('fee percent', () => {
    it('cannot be set to invalid value', async () => {
      await expect(
        createVault(admin, {
          capacity,
          feePercent: 10001,
          metadataIpfsHash,
        })
      ).to.be.revertedWith('InvalidFeePercent')
    })
  })

  describe('validators root', () => {
    const newValidatorsRoot = '0x059a8487a1ce461e9670c4646ef85164ae8791613866d28c972fb351dc45c606'
    let vault: EthVault

    beforeEach('deploy vault', async () => {
      vault = await createVault(admin, {
        capacity,
        feePercent,
        metadataIpfsHash,
      })
      await vault.connect(admin).setKeysManager(keysManager.address)
    })

    it('onlykeys manager can update', async () => {
      await expect(vault.connect(admin).setValidatorsRoot(newValidatorsRoot)).to.be.revertedWith(
        'AccessDenied'
      )
    })

    it('can update', async () => {
      const receipt = await vault.connect(keysManager).setValidatorsRoot(newValidatorsRoot)
      await expect(receipt)
        .to.emit(vault, 'ValidatorsRootUpdated')
        .withArgs(keysManager.address, newValidatorsRoot)
      await snapshotGasCost(receipt)
    })
  })

  describe('keys manager', () => {
    let vault: EthVault

    beforeEach('deploy vault', async () => {
      vault = await createVault(admin, {
        capacity,
        feePercent,
        metadataIpfsHash,
      })
    })

    it('cannot be updated by anyone', async () => {
      await expect(vault.connect(other).setKeysManager(keysManager.address)).to.be.revertedWith(
        'AccessDenied'
      )
    })

    it('cannot set to zero address', async () => {
      await expect(vault.connect(admin).setKeysManager(ZERO_ADDRESS)).to.be.revertedWith(
        'ZeroAddress'
      )
    })

    it('can be updated by admin', async () => {
      // initially equals to admin
      expect(await vault.keysManager()).to.be.eq(admin.address)
      const receipt = await vault.connect(admin).setKeysManager(keysManager.address)
      await expect(receipt)
        .to.emit(vault, 'KeysManagerUpdated')
        .withArgs(admin.address, keysManager.address)
      expect(await vault.keysManager()).to.be.eq(keysManager.address)
      await snapshotGasCost(receipt)
    })
  })

  describe('fee recipient', () => {
    let vault: EthVault

    beforeEach('deploy vault', async () => {
      vault = await createVault(admin, {
        capacity,
        feePercent,
        metadataIpfsHash,
      })
      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
    })

    it('only admin can update', async () => {
      await expect(
        vault.connect(other).setFeeRecipient(newFeeRecipient.address)
      ).to.be.revertedWith('AccessDenied')
    })

    it('cannot set to zero address', async () => {
      await expect(vault.connect(admin).setFeeRecipient(ZERO_ADDRESS)).to.be.revertedWith(
        'InvalidFeeRecipient'
      )
    })

    it('cannot update when not harvested', async () => {
      await updateRewards(keeper, [{ vault: vault.address, reward: 1, unlockedMevReward: 0 }])
      await updateRewards(keeper, [{ vault: vault.address, reward: 2, unlockedMevReward: 0 }])
      await expect(
        vault.connect(admin).setFeeRecipient(newFeeRecipient.address)
      ).to.be.revertedWith('NotHarvested')
    })

    it('can update', async () => {
      expect(await vault.feeRecipient()).to.be.eq(admin.address)
      const receipt = await vault.connect(admin).setFeeRecipient(newFeeRecipient.address)
      await expect(receipt)
        .to.emit(vault, 'FeeRecipientUpdated')
        .withArgs(admin.address, newFeeRecipient.address)
      expect(await vault.feeRecipient()).to.be.eq(newFeeRecipient.address)
      await snapshotGasCost(receipt)
    })
  })

  describe('metadata IPFS hash', () => {
    let vault: EthVault
    const newMetadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'

    beforeEach('deploy vault', async () => {
      vault = await createVault(admin, {
        capacity,
        feePercent,
        metadataIpfsHash,
      })
    })

    it('only admin can update', async () => {
      await expect(vault.connect(other).setMetadata(newMetadataIpfsHash)).to.be.revertedWith(
        'AccessDenied'
      )
      const receipt = await vault.connect(admin).setMetadata(newMetadataIpfsHash)
      await expect(receipt)
        .to.emit(vault, 'MetadataUpdated')
        .withArgs(admin.address, newMetadataIpfsHash)
      await snapshotGasCost(receipt)
    })
  })
})
