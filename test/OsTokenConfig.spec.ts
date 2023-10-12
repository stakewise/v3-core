import { ethers } from 'hardhat'
import { Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { OsTokenConfig } from '../typechain-types'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import {
  OSTOKEN_LIQ_BONUS,
  OSTOKEN_LIQ_THRESHOLD,
  OSTOKEN_LTV,
  OSTOKEN_REDEEM_TO_LTV,
  OSTOKEN_REDEEM_FROM_LTV,
  MAX_UINT16,
} from './shared/constants'
import snapshotGasCost from './shared/snapshotGasCost'

describe('OsTokenConfig', () => {
  const newConfig = {
    redeemFromLtvPercent: OSTOKEN_REDEEM_FROM_LTV + 1,
    redeemToLtvPercent: OSTOKEN_REDEEM_TO_LTV + 1,
    liqThresholdPercent: OSTOKEN_LIQ_THRESHOLD + 1,
    liqBonusPercent: OSTOKEN_LIQ_BONUS + 1,
    ltvPercent: OSTOKEN_LTV + 1,
  }
  let dao: Wallet, other: Wallet
  let osTokenConfig: OsTokenConfig

  beforeEach('deploy fixtures', async () => {
    ;[dao, other] = await (ethers as any).getSigners()
    ;({ osTokenConfig } = await loadFixture(ethVaultFixture))
  })

  it('updates in constructor', async () => {
    expect(await osTokenConfig.redeemFromLtvPercent()).to.be.eq(OSTOKEN_REDEEM_FROM_LTV)
    expect(await osTokenConfig.redeemToLtvPercent()).to.be.eq(OSTOKEN_REDEEM_TO_LTV)
    expect(await osTokenConfig.liqThresholdPercent()).to.be.eq(OSTOKEN_LIQ_THRESHOLD)
    expect(await osTokenConfig.liqBonusPercent()).to.be.eq(OSTOKEN_LIQ_BONUS)
    expect(await osTokenConfig.ltvPercent()).to.be.eq(OSTOKEN_LTV)
  })

  it('cannot be updated by not owner', async () => {
    await expect(osTokenConfig.connect(other).updateConfig(newConfig)).to.revertedWithCustomError(
      osTokenConfig,
      'OwnableUnauthorizedAccount'
    )
  })

  it('fails with invalid redeem params', async () => {
    await expect(
      osTokenConfig
        .connect(dao)
        .updateConfig({ ...newConfig, redeemToLtvPercent: 9000, redeemFromLtvPercent: 8900 })
    ).to.revertedWithCustomError(osTokenConfig, 'InvalidRedeemFromLtvPercent')
  })

  it('can disable redeems for all positions', async () => {
    await expect(
      osTokenConfig.connect(dao).updateConfig({
        ...newConfig,
        redeemFromLtvPercent: MAX_UINT16,
        redeemToLtvPercent: MAX_UINT16,
      })
    ).to.emit(osTokenConfig, 'OsTokenConfigUpdated')
  })

  it('can enable redeems for all positions', async () => {
    await expect(
      osTokenConfig
        .connect(dao)
        .updateConfig({ ...newConfig, redeemFromLtvPercent: MAX_UINT16, redeemToLtvPercent: 0 })
    ).to.emit(osTokenConfig, 'OsTokenConfigUpdated')
  })

  it('fails with invalid liqThresholdPercent', async () => {
    await expect(
      osTokenConfig.connect(dao).updateConfig({ ...newConfig, liqThresholdPercent: 0 })
    ).to.revertedWithCustomError(osTokenConfig, 'InvalidLiqThresholdPercent')

    await expect(
      osTokenConfig.connect(dao).updateConfig({ ...newConfig, liqThresholdPercent: 10000 })
    ).to.revertedWithCustomError(osTokenConfig, 'InvalidLiqThresholdPercent')
  })

  it('fails with invalid liqBonusPercent', async () => {
    await expect(
      osTokenConfig.connect(dao).updateConfig({ ...newConfig, liqBonusPercent: 9999 })
    ).to.revertedWithCustomError(osTokenConfig, 'InvalidLiqBonusPercent')

    await expect(
      osTokenConfig
        .connect(dao)
        .updateConfig({ ...newConfig, liqThresholdPercent: 9500, liqBonusPercent: 11000 })
    ).to.revertedWithCustomError(osTokenConfig, 'InvalidLiqBonusPercent')
  })

  it('can disable liqBonusPercent', async () => {
    await expect(
      osTokenConfig.connect(dao).updateConfig({ ...newConfig, liqBonusPercent: 10000 })
    ).to.emit(osTokenConfig, 'OsTokenConfigUpdated')
  })

  it('fails with invalid ltvPercent', async () => {
    await expect(
      osTokenConfig.connect(dao).updateConfig({ ...newConfig, ltvPercent: 0 })
    ).to.revertedWithCustomError(osTokenConfig, 'InvalidLtvPercent')

    await expect(
      osTokenConfig
        .connect(dao)
        .updateConfig({ ...newConfig, ltvPercent: newConfig.liqThresholdPercent + 1 })
    ).to.revertedWithCustomError(osTokenConfig, 'InvalidLtvPercent')
  })

  it('owner can update config', async () => {
    const tx = await osTokenConfig.connect(dao).updateConfig(newConfig)
    await expect(tx)
      .to.emit(osTokenConfig, 'OsTokenConfigUpdated')
      .withArgs(
        newConfig.redeemFromLtvPercent,
        newConfig.redeemToLtvPercent,
        newConfig.liqThresholdPercent,
        newConfig.liqBonusPercent,
        newConfig.ltvPercent
      )

    const config = await osTokenConfig.getConfig()
    expect(await config[0]).to.be.eq(newConfig.redeemFromLtvPercent)
    expect(await config[1]).to.be.eq(newConfig.redeemToLtvPercent)
    expect(await config[2]).to.be.eq(newConfig.liqThresholdPercent)
    expect(await config[3]).to.be.eq(newConfig.liqBonusPercent)
    expect(await config[4]).to.be.eq(newConfig.ltvPercent)

    expect(await osTokenConfig.redeemFromLtvPercent()).to.be.eq(newConfig.redeemFromLtvPercent)
    expect(await osTokenConfig.redeemToLtvPercent()).to.be.eq(newConfig.redeemToLtvPercent)
    expect(await osTokenConfig.liqThresholdPercent()).to.be.eq(newConfig.liqThresholdPercent)
    expect(await osTokenConfig.liqBonusPercent()).to.be.eq(newConfig.liqBonusPercent)
    expect(await osTokenConfig.ltvPercent()).to.be.eq(newConfig.ltvPercent)
    await snapshotGasCost(tx)
  })
})
