import { ethers, waffle } from 'hardhat'
import { Wallet } from 'ethers'
import { EthVault } from '../typechain-types'
import { vaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import snapshotGasCost from './shared/snapshotGasCost'
import { increaseTime } from './shared/utils'
import { MAX_UINT128, ZERO_BYTES32 } from './shared/constants'

const createFixtureLoader = waffle.createFixtureLoader

type ThenArg<T> = T extends PromiseLike<infer U> ? U : T

describe('EthVault - settings', () => {
  const maxTotalAssets = ethers.utils.parseEther('1000')
  const feePercent = 1000
  let operator: Wallet, other: Wallet
  let vault: EthVault
  let settingUpdateTimeout: number
  let settingUpdateDelay: number

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createEthVault: ThenArg<ReturnType<typeof vaultFixture>>['createEthVault']

  before('create fixture loader', async () => {
    ;[operator, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([operator, other])
  })

  beforeEach('deploy fixture', async () => {
    ;({ createEthVault } = await loadFixture(vaultFixture))
    vault = await createEthVault(operator.address, maxTotalAssets, feePercent)
    settingUpdateDelay = (await vault.settingUpdateDelay()).toNumber()
    settingUpdateTimeout = (await vault.settingsUpdateTimeout()).toNumber()
  })

  describe('max total assets', () => {
    const newMaxTotalAssets = maxTotalAssets.add(100)

    it('cannot be applied without init', async () => {
      await expect(vault.connect(operator).applyMaxTotalAssets()).to.be.revertedWith(
        'SettingUpdateFailed()'
      )
    })

    it('cannot be applied too early', async () => {
      await vault.connect(operator).initMaxTotalAssets(newMaxTotalAssets)
      await expect(vault.connect(operator).applyMaxTotalAssets()).to.be.revertedWith(
        'SettingUpdateFailed()'
      )
    })

    it('cannot be applied too late', async () => {
      await vault.connect(operator).initMaxTotalAssets(newMaxTotalAssets)
      await increaseTime(settingUpdateTimeout)
      await expect(vault.connect(operator).applyMaxTotalAssets()).to.be.revertedWith(
        'SettingUpdateFailed()'
      )
    })

    it('cannot be applied twice', async () => {
      await vault.connect(operator).initMaxTotalAssets(newMaxTotalAssets)
      await increaseTime(settingUpdateDelay)
      await vault.connect(operator).applyMaxTotalAssets()
      await expect(vault.connect(operator).applyMaxTotalAssets()).to.be.revertedWith(
        'SettingUpdateFailed()'
      )
    })

    it('only operator can init', async () => {
      await expect(vault.connect(other).initMaxTotalAssets(maxTotalAssets)).to.be.revertedWith(
        'NotOperator()'
      )
    })

    it('only operator can apply', async () => {
      await expect(vault.connect(other).applyMaxTotalAssets()).to.be.revertedWith('NotOperator()')
    })

    it('new value can be canceled', async () => {
      await vault.connect(operator).initMaxTotalAssets(newMaxTotalAssets)
      await increaseTime(settingUpdateTimeout)
      await vault.connect(operator).initMaxTotalAssets(newMaxTotalAssets)
      await expect(vault.connect(operator).applyMaxTotalAssets()).to.be.revertedWith(
        'SettingUpdateFailed()'
      )
    })

    it('new value can be applied', async () => {
      let receipt = await vault.connect(operator).initMaxTotalAssets(newMaxTotalAssets)
      expect(receipt)
        .to.emit(vault, 'MaxTotalAssetsInitiated')
        .withArgs(operator.address, newMaxTotalAssets)
      expect(await vault.maxTotalAssets()).to.be.eq(maxTotalAssets)
      expect(await vault.nextMaxTotalAssets()).to.be.eq(newMaxTotalAssets)
      await snapshotGasCost(receipt)

      await increaseTime(settingUpdateDelay)
      receipt = await vault.connect(operator).applyMaxTotalAssets()
      expect(receipt)
        .to.emit(vault, 'MaxTotalAssetsUpdated')
        .withArgs(operator.address, newMaxTotalAssets)
      expect(await vault.maxTotalAssets()).to.be.eq(newMaxTotalAssets)
      expect(await vault.nextMaxTotalAssets()).to.be.eq(newMaxTotalAssets)
      await snapshotGasCost(receipt)
    })

    it('can be set to unlimited', async () => {
      let receipt = await vault.connect(operator).initMaxTotalAssets(MAX_UINT128)
      expect(receipt)
        .to.emit(vault, 'MaxTotalAssetsInitiated')
        .withArgs(operator.address, MAX_UINT128)
      expect(await vault.maxTotalAssets()).to.be.eq(maxTotalAssets)
      expect(await vault.nextMaxTotalAssets()).to.be.eq(MAX_UINT128)
      await snapshotGasCost(receipt)

      await increaseTime(settingUpdateDelay)
      receipt = await vault.connect(operator).applyMaxTotalAssets()
      expect(receipt)
        .to.emit(vault, 'MaxTotalAssetsUpdated')
        .withArgs(operator.address, MAX_UINT128)
      expect(await vault.maxTotalAssets()).to.be.eq(MAX_UINT128)
      expect(await vault.nextMaxTotalAssets()).to.be.eq(MAX_UINT128)
      await snapshotGasCost(receipt)
    })
  })

  describe('fee percent', () => {
    const newFeePercent = feePercent + 1000

    it('cannot be applied without init', async () => {
      await expect(vault.connect(operator).applyFeePercent()).to.be.revertedWith(
        'SettingUpdateFailed()'
      )
    })

    it('cannot be applied too early', async () => {
      await vault.connect(operator).initFeePercent(newFeePercent)
      await expect(vault.connect(operator).applyFeePercent()).to.be.revertedWith(
        'SettingUpdateFailed()'
      )
    })

    it('cannot be applied too late', async () => {
      await vault.connect(operator).initFeePercent(newFeePercent)
      await increaseTime(settingUpdateTimeout)
      await expect(vault.connect(operator).applyFeePercent()).to.be.revertedWith(
        'SettingUpdateFailed()'
      )
    })

    it('cannot be applied twice', async () => {
      await vault.connect(operator).initFeePercent(newFeePercent)
      await increaseTime(settingUpdateDelay)
      await vault.connect(operator).applyFeePercent()
      await expect(vault.connect(operator).applyFeePercent()).to.be.revertedWith(
        'SettingUpdateFailed()'
      )
    })

    it('only operator can init', async () => {
      await expect(vault.connect(other).initFeePercent(feePercent)).to.be.revertedWith(
        'NotOperator()'
      )
    })

    it('only operator can apply', async () => {
      await expect(vault.connect(other).applyFeePercent()).to.be.revertedWith('NotOperator()')
    })

    it('new value can be canceled', async () => {
      await vault.connect(operator).initFeePercent(newFeePercent)
      await increaseTime(settingUpdateTimeout)
      await vault.connect(operator).initFeePercent(newFeePercent)
      await expect(vault.connect(operator).applyFeePercent()).to.be.revertedWith(
        'SettingUpdateFailed()'
      )
    })

    it('new value can be applied', async () => {
      let receipt = await vault.connect(operator).initFeePercent(newFeePercent)
      expect(receipt)
        .to.emit(vault, 'FeePercentInitiated')
        .withArgs(operator.address, newFeePercent)
      expect(await vault.feePercent()).to.be.eq(feePercent)
      expect(await vault.nextFeePercent()).to.be.eq(newFeePercent)
      await snapshotGasCost(receipt)

      await increaseTime(settingUpdateDelay)
      receipt = await vault.connect(operator).applyFeePercent()
      expect(receipt).to.emit(vault, 'FeePercentUpdated').withArgs(operator.address, newFeePercent)
      expect(await vault.feePercent()).to.be.eq(newFeePercent)
      expect(await vault.nextFeePercent()).to.be.eq(newFeePercent)
      await snapshotGasCost(receipt)
    })

    it('cannot init with invalid value', async () => {
      await expect(vault.connect(operator).initFeePercent(10001)).to.be.revertedWith(
        'InvalidSetting()'
      )
    })
  })

  describe('operator', () => {
    it('only operator can update', async () => {
      await expect(vault.connect(other).setOperator(other.address)).to.be.revertedWith(
        'NotOperator()'
      )
    })

    it('cannot update with invalid value', async () => {
      await expect(vault.connect(operator).setOperator(operator.address)).to.be.revertedWith(
        'InvalidSetting()'
      )
    })

    it('can update', async () => {
      const receipt = await vault.connect(operator).setOperator(other.address)
      expect(receipt).to.emit(vault, 'OperatorUpdated').withArgs(operator.address, other.address)
      expect(await vault.operator()).to.be.eq(other.address)
      await snapshotGasCost(receipt)
    })
  })

  describe('validators root', () => {
    const newValidatorsRoot = '0x059a8487a1ce461e9670c4646ef85164ae8791613866d28c972fb351dc45c606'
    const newValidatorsIpfsHash = '/ipfs/QmfPnyNojfyqoi9yqS3jMp16GGiTQee4bdCXJC64KqvTgc'

    it('only operator can update', async () => {
      await expect(
        vault.connect(other).setValidatorsRoot(newValidatorsRoot, newValidatorsIpfsHash)
      ).to.be.revertedWith('NotOperator()')
    })

    it('cannot update with invalid value', async () => {
      await expect(
        vault.connect(operator).setValidatorsRoot(ZERO_BYTES32, newValidatorsIpfsHash)
      ).to.be.revertedWith('InvalidSetting()')
    })

    it('can update', async () => {
      const receipt = await vault
        .connect(operator)
        .setValidatorsRoot(newValidatorsRoot, newValidatorsIpfsHash)
      expect(receipt)
        .to.emit(vault, 'ValidatorsRootUpdated')
        .withArgs(operator.address, newValidatorsRoot, newValidatorsIpfsHash)
      expect(await vault.validatorsRoot()).to.be.eq(newValidatorsRoot)
      await snapshotGasCost(receipt)
    })
  })
})
