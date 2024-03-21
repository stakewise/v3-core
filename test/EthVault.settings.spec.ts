import { ethers } from 'hardhat'
import { Contract, Wallet } from 'ethers'

import { EthVault, Keeper, DepositDataManager } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import snapshotGasCost from './shared/snapshotGasCost'
import { ZERO_ADDRESS } from './shared/constants'
import { collateralizeEthVault, updateRewards } from './shared/rewards'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'

describe('EthVault - settings', () => {
  const capacity = ethers.parseEther('1000')
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'

  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVault']
  let admin: Wallet, keysManager: Wallet, other: Wallet, newFeeRecipient: Wallet
  let keeper: Keeper, validatorsRegistry: Contract, depositDataManager: DepositDataManager

  before('create fixture loader', async () => {
    ;[admin, keysManager, other, newFeeRecipient] = (await (ethers as any).getSigners()).slice(1, 5)
  })

  beforeEach('deploy fixture', async () => {
    ;({
      keeper,
      validatorsRegistry,
      depositDataManager,
      createEthVault: createVault,
    } = await loadFixture(ethVaultFixture))
  })

  describe('fee percent', () => {
    it('cannot be set to invalid value', async () => {
      const vault = await createVault(
        admin,
        {
          capacity,
          feePercent: 10000,
          metadataIpfsHash,
        },
        false,
        true
      )
      await expect(
        createVault(
          admin,
          {
            capacity,
            feePercent: 10001,
            metadataIpfsHash,
          },
          false,
          true
        )
      ).to.be.revertedWithCustomError(vault, 'InvalidFeePercent')
    })
  })

  describe('keys manager', () => {
    let vault: EthVault

    beforeEach('deploy vault', async () => {
      vault = await createVault(
        admin,
        {
          capacity,
          feePercent,
          metadataIpfsHash,
        },
        false,
        true
      )
    })

    it('cannot be updated by anyone', async () => {
      await expect(
        vault.connect(other).setKeysManager(keysManager.address)
      ).to.be.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('can be updated by admin', async () => {
      // initially equals to admin
      expect(await vault.keysManager()).to.be.eq(await depositDataManager.getAddress())
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
      vault = await createVault(
        admin,
        {
          capacity,
          feePercent,
          metadataIpfsHash,
        },
        false,
        true
      )
      await collateralizeEthVault(vault, keeper, depositDataManager, admin, validatorsRegistry)
    })

    it('only admin can update', async () => {
      await expect(
        vault.connect(other).setFeeRecipient(newFeeRecipient.address)
      ).to.be.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('cannot set to zero address', async () => {
      await expect(
        vault.connect(admin).setFeeRecipient(ZERO_ADDRESS)
      ).to.be.revertedWithCustomError(vault, 'InvalidFeeRecipient')
    })

    it('cannot update when not harvested', async () => {
      await updateRewards(keeper, [
        { vault: await vault.getAddress(), reward: 1n, unlockedMevReward: 0n },
      ])
      await updateRewards(keeper, [
        { vault: await vault.getAddress(), reward: 2n, unlockedMevReward: 0n },
      ])
      await expect(
        vault.connect(admin).setFeeRecipient(newFeeRecipient.address)
      ).to.be.revertedWithCustomError(vault, 'NotHarvested')
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
      vault = await createVault(
        admin,
        {
          capacity,
          feePercent,
          metadataIpfsHash,
        },
        false,
        true
      )
    })

    it('only admin can update', async () => {
      await expect(
        vault.connect(other).setMetadata(newMetadataIpfsHash)
      ).to.be.revertedWithCustomError(vault, 'AccessDenied')
      const receipt = await vault.connect(admin).setMetadata(newMetadataIpfsHash)
      await expect(receipt)
        .to.emit(vault, 'MetadataUpdated')
        .withArgs(admin.address, newMetadataIpfsHash)
      await snapshotGasCost(receipt)
    })
  })
})
