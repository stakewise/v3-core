import { ethers, waffle } from 'hardhat'
import { Wallet } from 'ethers'
import { OsTokenConfig } from '../typechain-types'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import {
  MAX_UINT256,
  OSTOKEN_LIQ_BONUS,
  OSTOKEN_LIQ_THRESHOLD,
  OSTOKEN_LTV,
  OSTOKEN_REDEEM_MAX_HF,
  OSTOKEN_REDEEM_START_HF,
} from './shared/constants'
import snapshotGasCost from './shared/snapshotGasCost'

const createFixtureLoader = waffle.createFixtureLoader

describe('OsTokenConfig', () => {
  const newConfig = {
    redeemStartHealthFactor: OSTOKEN_REDEEM_START_HF.add(1),
    redeemMaxHealthFactor: OSTOKEN_REDEEM_MAX_HF.add(1),
    liqThresholdPercent: OSTOKEN_LIQ_THRESHOLD + 1,
    liqBonusPercent: OSTOKEN_LIQ_BONUS + 1,
    ltvPercent: OSTOKEN_LTV + 1,
  }
  let owner: Wallet, other: Wallet
  let osTokenConfig: OsTokenConfig
  let loadFixture: ReturnType<typeof createFixtureLoader>

  before('create fixture loader', async () => {
    ;[owner, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([owner])
  })

  beforeEach('deploy fixtures', async () => {
    ;({ osTokenConfig } = await loadFixture(ethVaultFixture))
  })

  it('updates in constructor', async () => {
    expect(await osTokenConfig.redeemStartHealthFactor()).to.be.eq(OSTOKEN_REDEEM_START_HF)
    expect(await osTokenConfig.redeemMaxHealthFactor()).to.be.eq(OSTOKEN_REDEEM_MAX_HF)
    expect(await osTokenConfig.liqThresholdPercent()).to.be.eq(OSTOKEN_LIQ_THRESHOLD)
    expect(await osTokenConfig.liqBonusPercent()).to.be.eq(OSTOKEN_LIQ_BONUS)
    expect(await osTokenConfig.ltvPercent()).to.be.eq(OSTOKEN_LTV)
  })

  it('cannot be updated by not owner', async () => {
    await expect(
      osTokenConfig
        .connect(other)
        .updateConfig(
          newConfig.redeemStartHealthFactor,
          newConfig.redeemMaxHealthFactor,
          newConfig.liqThresholdPercent,
          newConfig.liqBonusPercent,
          newConfig.ltvPercent
        )
    ).to.revertedWith('Ownable: caller is not the owner')
  })

  it('fails with invalid redeemStartHealthFactor', async () => {
    await expect(
      osTokenConfig
        .connect(owner)
        .updateConfig(
          newConfig.redeemMaxHealthFactor.add(1),
          newConfig.redeemMaxHealthFactor,
          newConfig.liqThresholdPercent,
          newConfig.liqBonusPercent,
          newConfig.ltvPercent
        )
    ).to.revertedWith('InvalidRedeemStartHealthFactor')
  })

  it('can disable redeems for all positions', async () => {
    await expect(
      osTokenConfig
        .connect(owner)
        .updateConfig(
          MAX_UINT256,
          MAX_UINT256,
          newConfig.liqThresholdPercent,
          newConfig.liqBonusPercent,
          newConfig.ltvPercent
        )
    ).to.emit(osTokenConfig, 'OsTokenConfigUpdated')
  })

  it('can enable redeems for all positions', async () => {
    await expect(
      osTokenConfig
        .connect(owner)
        .updateConfig(
          0,
          MAX_UINT256,
          newConfig.liqThresholdPercent,
          newConfig.liqBonusPercent,
          newConfig.ltvPercent
        )
    ).to.emit(osTokenConfig, 'OsTokenConfigUpdated')
  })

  it('fails with invalid liqThresholdPercent', async () => {
    await expect(
      osTokenConfig
        .connect(owner)
        .updateConfig(
          newConfig.redeemMaxHealthFactor,
          newConfig.redeemMaxHealthFactor,
          0,
          newConfig.liqBonusPercent,
          newConfig.ltvPercent
        )
    ).to.revertedWith('InvalidLiqThresholdPercent')

    await expect(
      osTokenConfig
        .connect(owner)
        .updateConfig(
          newConfig.redeemMaxHealthFactor,
          newConfig.redeemMaxHealthFactor,
          10000,
          newConfig.liqBonusPercent,
          newConfig.ltvPercent
        )
    ).to.revertedWith('InvalidLiqThresholdPercent')
  })

  it('fails with invalid liqBonusPercent', async () => {
    await expect(
      osTokenConfig
        .connect(owner)
        .updateConfig(
          newConfig.redeemMaxHealthFactor,
          newConfig.redeemMaxHealthFactor,
          newConfig.liqThresholdPercent,
          9999,
          newConfig.ltvPercent
        )
    ).to.revertedWith('InvalidLiqBonusPercent')

    await expect(
      osTokenConfig
        .connect(owner)
        .updateConfig(
          newConfig.redeemMaxHealthFactor,
          newConfig.redeemMaxHealthFactor,
          9500,
          11000,
          newConfig.ltvPercent
        )
    ).to.revertedWith('InvalidLiqBonusPercent')
  })

  it('can disable liqBonusPercent', async () => {
    await expect(
      osTokenConfig
        .connect(owner)
        .updateConfig(
          newConfig.redeemMaxHealthFactor,
          newConfig.redeemMaxHealthFactor,
          newConfig.liqThresholdPercent,
          10000,
          newConfig.ltvPercent
        )
    ).to.emit(osTokenConfig, 'OsTokenConfigUpdated')
  })

  it('fails with invalid ltvPercent', async () => {
    await expect(
      osTokenConfig
        .connect(owner)
        .updateConfig(
          newConfig.redeemMaxHealthFactor,
          newConfig.redeemMaxHealthFactor,
          newConfig.liqThresholdPercent,
          newConfig.liqBonusPercent,
          0
        )
    ).to.revertedWith('InvalidLtvPercent')

    await expect(
      osTokenConfig
        .connect(owner)
        .updateConfig(
          newConfig.redeemMaxHealthFactor,
          newConfig.redeemMaxHealthFactor,
          newConfig.liqThresholdPercent,
          newConfig.liqBonusPercent,
          newConfig.liqThresholdPercent + 1
        )
    ).to.revertedWith('InvalidLtvPercent')
  })

  it('owner can update config', async () => {
    const tx = await osTokenConfig
      .connect(owner)
      .updateConfig(
        newConfig.redeemStartHealthFactor,
        newConfig.redeemMaxHealthFactor,
        newConfig.liqThresholdPercent,
        newConfig.liqBonusPercent,
        newConfig.ltvPercent
      )
    await expect(tx)
      .to.emit(osTokenConfig, 'OsTokenConfigUpdated')
      .withArgs(
        newConfig.redeemStartHealthFactor,
        newConfig.redeemMaxHealthFactor,
        newConfig.liqThresholdPercent,
        newConfig.liqBonusPercent,
        newConfig.ltvPercent
      )

    expect(await osTokenConfig.redeemStartHealthFactor()).to.be.eq(
      newConfig.redeemStartHealthFactor
    )
    expect(await osTokenConfig.redeemMaxHealthFactor()).to.be.eq(newConfig.redeemMaxHealthFactor)
    expect(await osTokenConfig.liqThresholdPercent()).to.be.eq(newConfig.liqThresholdPercent)
    expect(await osTokenConfig.liqBonusPercent()).to.be.eq(newConfig.liqBonusPercent)
    expect(await osTokenConfig.ltvPercent()).to.be.eq(newConfig.ltvPercent)
    await snapshotGasCost(tx)
  })
})
