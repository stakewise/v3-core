import { ethers } from 'hardhat'
import { parseEther, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { OsTokenConfig } from '../typechain-types'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import {
  OSTOKEN_LIQ_BONUS,
  OSTOKEN_LIQ_THRESHOLD,
  OSTOKEN_LTV,
  ZERO_ADDRESS,
  MAX_UINT64,
} from './shared/constants'
import snapshotGasCost from './shared/snapshotGasCost'
import { MAINNET_FORK } from '../helpers/constants'

describe('OsTokenConfig', () => {
  const newConfig = {
    liqThresholdPercent: OSTOKEN_LIQ_THRESHOLD + 1n,
    liqBonusPercent: OSTOKEN_LIQ_BONUS + 1n,
    ltvPercent: OSTOKEN_LTV + 1n,
  }
  const maxPercent = parseEther('1')
  let dao: Wallet, other: Wallet
  let osTokenConfig: OsTokenConfig

  beforeEach('deploy fixtures', async () => {
    ;[dao, other] = await (ethers as any).getSigners()
    ;({ osTokenConfig } = await loadFixture(ethVaultFixture))
  })

  it('updates in constructor', async () => {
    if (MAINNET_FORK.enabled) return
    const config = await osTokenConfig.getConfig(ZERO_ADDRESS)
    expect(config.liqThresholdPercent).to.be.eq(OSTOKEN_LIQ_THRESHOLD)
    expect(config.liqBonusPercent).to.be.eq(OSTOKEN_LIQ_BONUS)
    expect(config.ltvPercent).to.be.eq(OSTOKEN_LTV)
    expect(await osTokenConfig.redeemer()).to.eq(dao.address)
  })

  describe('redeemer', () => {
    it('not owner cannot update redeemer', async () => {
      await expect(
        osTokenConfig.connect(other).setRedeemer(other.address)
      ).to.revertedWithCustomError(osTokenConfig, 'OwnableUnauthorizedAccount')
    })

    it('cannot set redeemer to the same address', async () => {
      await expect(osTokenConfig.connect(dao).setRedeemer(dao.address)).to.revertedWithCustomError(
        osTokenConfig,
        'ValueNotChanged'
      )
    })

    it('owner can update redeemer', async () => {
      const tx = await osTokenConfig.connect(dao).setRedeemer(other.address)
      await expect(tx).to.emit(osTokenConfig, 'RedeemerUpdated').withArgs(other.address)
      expect(await osTokenConfig.redeemer()).to.be.eq(other.address)
      await snapshotGasCost(tx)
    })
  })

  describe('config', () => {
    it('not owner cannot update config', async () => {
      await expect(
        osTokenConfig.connect(other).updateConfig(other.address, newConfig)
      ).to.revertedWithCustomError(osTokenConfig, 'OwnableUnauthorizedAccount')
    })

    it('fails with invalid ltvPercent', async () => {
      await expect(
        osTokenConfig.connect(dao).updateConfig(other.address, { ...newConfig, ltvPercent: 0 })
      ).to.revertedWithCustomError(osTokenConfig, 'InvalidLtvPercent')

      await expect(
        osTokenConfig
          .connect(dao)
          .updateConfig(other.address, { ...newConfig, ltvPercent: maxPercent + 1n })
      ).to.revertedWithCustomError(osTokenConfig, 'InvalidLtvPercent')
    })

    it('fails to disable liquidations with non zero liquidation bonus percent', async () => {
      await expect(
        osTokenConfig.connect(dao).updateConfig(other.address, {
          ...newConfig,
          liqThresholdPercent: MAX_UINT64,
          liqBonusPercent: 1n,
        })
      ).to.revertedWithCustomError(osTokenConfig, 'InvalidLiqBonusPercent')
    })

    it('fails with invalid liqThresholdPercent', async () => {
      await expect(
        osTokenConfig
          .connect(dao)
          .updateConfig(other.address, { ...newConfig, liqThresholdPercent: 0 })
      ).to.revertedWithCustomError(osTokenConfig, 'InvalidLiqThresholdPercent')

      await expect(
        osTokenConfig
          .connect(dao)
          .updateConfig(other.address, { ...newConfig, liqThresholdPercent: maxPercent })
      ).to.revertedWithCustomError(osTokenConfig, 'InvalidLiqThresholdPercent')

      await expect(
        osTokenConfig.connect(dao).updateConfig(other.address, {
          ...newConfig,
          ltvPercent: newConfig.liqThresholdPercent + 1n,
        })
      ).to.revertedWithCustomError(osTokenConfig, 'InvalidLiqThresholdPercent')
    })

    it('fails with invalid liqBonusPercent', async () => {
      await expect(
        osTokenConfig
          .connect(dao)
          .updateConfig(other.address, { ...newConfig, liqBonusPercent: maxPercent - 1n })
      ).to.revertedWithCustomError(osTokenConfig, 'InvalidLiqBonusPercent')

      await expect(
        osTokenConfig.connect(dao).updateConfig(other.address, {
          ...newConfig,
          liqThresholdPercent: parseEther('0.95'),
          liqBonusPercent: parseEther('1.1'),
        })
      ).to.revertedWithCustomError(osTokenConfig, 'InvalidLiqBonusPercent')
    })

    it('owner can update config for a vault', async () => {
      const tx = await osTokenConfig.connect(dao).updateConfig(other.address, newConfig)
      await expect(tx)
        .to.emit(osTokenConfig, 'OsTokenConfigUpdated')
        .withArgs(
          other.address,
          newConfig.liqBonusPercent,
          newConfig.liqThresholdPercent,
          newConfig.ltvPercent
        )
      const config = await osTokenConfig.getConfig(other.address)
      expect(config.liqThresholdPercent).to.be.eq(newConfig.liqThresholdPercent)
      expect(config.liqBonusPercent).to.be.eq(newConfig.liqBonusPercent)
      expect(config.ltvPercent).to.be.eq(newConfig.ltvPercent)

      const defaultConfig = await osTokenConfig.getConfig(dao.address)
      expect(defaultConfig.liqThresholdPercent).to.be.eq(OSTOKEN_LIQ_THRESHOLD)
      expect(defaultConfig.liqBonusPercent).to.be.eq(OSTOKEN_LIQ_BONUS)
      expect(defaultConfig.ltvPercent).to.be.eq(OSTOKEN_LTV)
      await snapshotGasCost(tx)
    })

    it('owner can update default config', async () => {
      const tx = await osTokenConfig.connect(dao).updateConfig(ZERO_ADDRESS, newConfig)
      await expect(tx)
        .to.emit(osTokenConfig, 'OsTokenConfigUpdated')
        .withArgs(
          ZERO_ADDRESS,
          newConfig.liqBonusPercent,
          newConfig.liqThresholdPercent,
          newConfig.ltvPercent
        )
      const config = await osTokenConfig.getConfig(dao.address)
      expect(config.liqThresholdPercent).to.be.eq(newConfig.liqThresholdPercent)
      expect(config.liqBonusPercent).to.be.eq(newConfig.liqBonusPercent)
      expect(config.ltvPercent).to.be.eq(newConfig.ltvPercent)
      await snapshotGasCost(tx)
    })
  })
})
