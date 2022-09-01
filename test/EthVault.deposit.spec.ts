import { ethers, waffle } from 'hardhat'
import { Wallet } from 'ethers'
import { EthVault, EthVaultMock } from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { vaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { PANIC_CODES, ZERO_ADDRESS } from './shared/constants'

const createFixtureLoader = waffle.createFixtureLoader
const parseEther = ethers.utils.parseEther

type ThenArg<T> = T extends PromiseLike<infer U> ? U : T

describe('EthVault - deposit', () => {
  let sender: Wallet, receiver: Wallet, other: Wallet
  let vault: EthVault

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createEthVault: ThenArg<ReturnType<typeof vaultFixture>>['createEthVault']
  let createEthVaultMock: ThenArg<ReturnType<typeof vaultFixture>>['createEthVaultMock']

  before('create fixture loader', async () => {
    ;[sender, receiver, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([sender, receiver, other])
  })

  beforeEach('deploy fixture', async () => {
    ;({ createEthVault, createEthVaultMock } = await loadFixture(vaultFixture))
    vault = await createEthVault()
  })

  describe('empty vault: no assets & no shares', () => {
    it('status', async () => {
      expect(await vault.totalAssets()).to.equal(0)
      expect(await vault.totalSupply()).to.equal(0)
    })

    it('deposit', async () => {
      const amount = parseEther('1')
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
    beforeEach(async () => {
      await other.sendTransaction({
        to: await vault.feesEscrow(),
        value: parseEther('1'),
      })
    })

    it('status', async () => {
      expect(await vault.totalAssets()).to.eq(parseEther('1'))
    })

    it('deposit', async () => {
      const amount = parseEther('1')
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
      ethVaultMock = await createEthVaultMock(1)
      await ethVaultMock.mockMint(receiver.address, parseEther('1'))
    })

    it('status', async () => {
      expect(await ethVaultMock.totalAssets()).to.eq('0')
    })

    it('deposit', async () => {
      const amount = parseEther('1')
      await expect(
        ethVaultMock.connect(sender).deposit(receiver.address, { value: amount })
      ).to.be.revertedWith(PANIC_CODES.DIVISION_BY_ZERO)
    })
  })

  describe('full vault: assets & shares', () => {
    beforeEach(async () => {
      await vault.connect(other).deposit(other.address, { value: parseEther('99') })
      await other.sendTransaction({
        to: await vault.feesEscrow(),
        value: parseEther('1'),
      })
    })

    it('status', async () => {
      expect(await vault.totalAssets()).to.eq(parseEther('100'))
    })

    it('deposit', async () => {
      const amount = parseEther('100')
      const expectedShares = parseEther('99')
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
