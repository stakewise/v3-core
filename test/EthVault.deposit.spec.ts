import { ethers, waffle } from 'hardhat'
import { Wallet } from 'ethers'
import { EthVault, EthVaultMock } from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { vaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { PANIC_CODES, ZERO_ADDRESS } from './shared/constants'

const createFixtureLoader = waffle.createFixtureLoader
const parseEther = ethers.utils.parseEther
const ether = parseEther('1')

type ThenArg<T> = T extends PromiseLike<infer U> ? U : T

describe('EthVault - deposit', () => {
  const maxTotalAssets = parseEther('1000')
  const feePercent = 1000
  let keeper: Wallet, sender: Wallet, receiver: Wallet, operator: Wallet, other: Wallet
  let vault: EthVault

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createEthVault: ThenArg<ReturnType<typeof vaultFixture>>['createEthVault']
  let createEthVaultMock: ThenArg<ReturnType<typeof vaultFixture>>['createEthVaultMock']

  before('create fixture loader', async () => {
    ;[keeper, sender, receiver, operator, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([keeper, sender, receiver, other])
  })

  beforeEach('deploy fixture', async () => {
    ;({ createEthVault, createEthVaultMock } = await loadFixture(vaultFixture))
    vault = await createEthVault(keeper.address, operator.address, maxTotalAssets, feePercent)
  })

  describe('empty vault: no assets & no shares', () => {
    it('status', async () => {
      expect(await vault.totalAssets()).to.equal(0)
      expect(await vault.totalSupply()).to.equal(0)
    })

    it('deposit', async () => {
      const amount = ether
      expect(await vault.convertToShares(amount)).to.eq(amount)
      const receipt = await vault.connect(sender).deposit(receiver.address, { value: amount })
      expect(await vault.balanceOf(receiver.address)).to.eq(amount)

      await expect(receipt)
        .to.emit(vault, 'Transfer')
        .withArgs(ZERO_ADDRESS, receiver.address, amount)
      await expect(receipt)
        .to.emit(vault, 'Deposit')
        .withArgs(sender.address, receiver.address, amount, amount)
      await snapshotGasCost(receipt)
    })
  })

  describe('partially empty vault: assets & no shares', () => {
    let vault: EthVaultMock
    beforeEach(async () => {
      vault = await createEthVaultMock(keeper.address, operator.address, maxTotalAssets, feePercent)
      await vault._setTotalStakedAssets(ether)
    })

    it('status', async () => {
      expect(await vault.totalAssets()).to.eq(ether)
    })

    it('deposit', async () => {
      const amount = ether
      expect(await vault.convertToShares(amount)).to.eq(amount)
      const receipt = await vault.connect(sender).deposit(receiver.address, { value: amount })
      expect(await vault.balanceOf(receiver.address)).to.eq(amount)

      await expect(receipt)
        .to.emit(vault, 'Transfer')
        .withArgs(ZERO_ADDRESS, receiver.address, amount)
      await expect(receipt)
        .to.emit(vault, 'Deposit')
        .withArgs(sender.address, receiver.address, amount, amount)
      await snapshotGasCost(receipt)
    })
  })

  describe('partially empty vault: shares & no assets', () => {
    let ethVaultMock: EthVaultMock

    beforeEach(async () => {
      ethVaultMock = await createEthVaultMock(
        keeper.address,
        operator.address,
        maxTotalAssets,
        feePercent
      )
      await ethVaultMock.mockMint(receiver.address, ether)
    })

    it('status', async () => {
      expect(await ethVaultMock.totalAssets()).to.eq('0')
    })

    it('deposit', async () => {
      await expect(
        ethVaultMock.connect(sender).deposit(receiver.address, { value: ether })
      ).to.be.revertedWith(PANIC_CODES.DIVISION_BY_ZERO)
    })
  })

  describe('full vault: assets & shares', () => {
    beforeEach(async () => {
      await vault.connect(other).deposit(other.address, { value: parseEther('100') })
    })

    it('status', async () => {
      expect(await vault.totalAssets()).to.eq(parseEther('100'))
    })

    it('fails with exceeded max total assets', async () => {
      await expect(
        vault.connect(sender).deposit(receiver.address, { value: parseEther('999') })
      ).to.be.revertedWith('MaxTotalAssetsExceeded()')
    })

    it('deposit', async () => {
      const amount = parseEther('100')
      const expectedShares = parseEther('100')
      expect(await vault.convertToShares(amount)).to.eq(expectedShares)

      const receipt = await vault.connect(sender).deposit(receiver.address, { value: amount })
      expect(await vault.balanceOf(receiver.address)).to.eq(expectedShares)

      await expect(receipt)
        .to.emit(vault, 'Transfer')
        .withArgs(ZERO_ADDRESS, receiver.address, expectedShares)
      await expect(receipt)
        .to.emit(vault, 'Deposit')
        .withArgs(sender.address, receiver.address, amount, expectedShares)
      await snapshotGasCost(receipt)
    })
  })
})
