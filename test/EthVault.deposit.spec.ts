import { ethers, waffle } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import { Keeper, EthVault, EthVaultMock, Oracles, IKeeperRewards } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import snapshotGasCost from './shared/snapshotGasCost'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { PANIC_CODES, ZERO_ADDRESS } from './shared/constants'
import { getRewardsRootProof, updateRewardsRoot } from './shared/rewards'
import { registerEthValidator } from './shared/validators'
import { setBalance } from './shared/utils'

const createFixtureLoader = waffle.createFixtureLoader
const ether = parseEther('1')

describe('EthVault - deposit', () => {
  const capacity = parseEther('1000')
  const feePercent = 1000
  const name = 'SW ETH Vault'
  const symbol = 'SW-ETH-1'
  const validatorsRoot = '0x059a8487a1ce461e9670c4646ef85164ae8791613866d28c972fb351dc45c606'
  const validatorsIpfsHash = '/ipfs/QmfPnyNojfyqoi9yqS3jMp16GGiTQee4bdCXJC64KqvTgc'
  const metadataIpfsHash = '/ipfs/QmanU2bk9VsJuxhBmvfgXaC44fXpcC8DNHNxPZKMpNXo37'
  let dao: Wallet, sender: Wallet, receiver: Wallet, admin: Wallet, other: Wallet
  let vault: EthVault, keeper: Keeper, oracles: Oracles, validatorsRegistry: Contract

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createVault']
  let getSignatures: ThenArg<ReturnType<typeof ethVaultFixture>>['getSignatures']
  let createVaultMock: ThenArg<ReturnType<typeof ethVaultFixture>>['createVaultMock']

  before('create fixture loader', async () => {
    ;[dao, sender, receiver, admin, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([dao])
  })

  beforeEach('deploy fixtures', async () => {
    ;({ createVault, createVaultMock, keeper, oracles, validatorsRegistry, getSignatures } =
      await loadFixture(ethVaultFixture))
    vault = await createVault(admin, {
      capacity,
      validatorsRoot,
      feePercent,
      name,
      symbol,
      validatorsIpfsHash,
      metadataIpfsHash,
    })
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
    let ethVaultMock: EthVaultMock
    beforeEach(async () => {
      ethVaultMock = await createVaultMock(admin, {
        capacity,
        validatorsRoot,
        feePercent,
        name,
        symbol,
        validatorsIpfsHash,
        metadataIpfsHash,
      })
      await ethVaultMock._setTotalAssets(ether)
    })

    it('status', async () => {
      expect(await ethVaultMock.totalAssets()).to.eq(ether)
    })

    it('deposit', async () => {
      const amount = ether
      expect(await ethVaultMock.convertToShares(amount)).to.eq(amount)
      const receipt = await ethVaultMock
        .connect(sender)
        .deposit(receiver.address, { value: amount })
      expect(await ethVaultMock.balanceOf(receiver.address)).to.eq(amount)

      await expect(receipt)
        .to.emit(ethVaultMock, 'Transfer')
        .withArgs(ZERO_ADDRESS, receiver.address, amount)
      await expect(receipt)
        .to.emit(ethVaultMock, 'Deposit')
        .withArgs(sender.address, receiver.address, amount, amount)
      await snapshotGasCost(receipt)
    })
  })

  describe('partially empty vault: shares & no assets', () => {
    let ethVaultMock: EthVaultMock

    beforeEach(async () => {
      ethVaultMock = await createVaultMock(admin, {
        capacity,
        validatorsRoot,
        feePercent,
        name,
        symbol,
        validatorsIpfsHash,
        metadataIpfsHash,
      })
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
      await vault.connect(other).deposit(other.address, { value: parseEther('10') })
    })

    it('status', async () => {
      expect(await vault.totalAssets()).to.eq(parseEther('10'))
    })

    it('fails with exceeded capacity', async () => {
      await expect(
        vault.connect(sender).deposit(receiver.address, { value: parseEther('999') })
      ).to.be.revertedWith('CapacityExceeded()')
    })

    it('fails when not harvested', async () => {
      await vault.connect(other).deposit(other.address, { value: parseEther('32') })
      await registerEthValidator(vault, oracles, keeper, validatorsRegistry, admin, getSignatures)
      await updateRewardsRoot(keeper, oracles, getSignatures, [
        { reward: parseEther('5'), vault: vault.address },
      ])
      await updateRewardsRoot(keeper, oracles, getSignatures, [
        { reward: parseEther('10'), vault: vault.address },
      ])
      await expect(
        vault.connect(sender).deposit(receiver.address, { value: parseEther('10') })
      ).to.be.revertedWith('NotHarvested()')
    })

    it('update state and deposit', async () => {
      await vault.connect(other).deposit(other.address, { value: parseEther('32') })
      await registerEthValidator(vault, oracles, keeper, validatorsRegistry, admin, getSignatures)

      let vaultReward = parseEther('10')
      await updateRewardsRoot(keeper, oracles, getSignatures, [
        { reward: vaultReward, vault: vault.address },
      ])

      vaultReward = vaultReward.add(parseEther('1'))
      const tree = await updateRewardsRoot(keeper, oracles, getSignatures, [
        { reward: vaultReward, vault: vault.address },
      ])

      const harvestParams: IKeeperRewards.HarvestParamsStruct = {
        rewardsRoot: tree.root,
        reward: vaultReward,
        proof: getRewardsRootProof(tree, { vault: vault.address, reward: vaultReward }),
      }
      await setBalance(await vault.mevEscrow(), parseEther('10'))
      await setBalance(await vault.address, parseEther('5'))
      await vault.connect(other).enterExitQueue(parseEther('32'), other.address, other.address)

      const amount = parseEther('100')
      const receipt = await vault
        .connect(sender)
        .updateStateAndDeposit(receiver.address, harvestParams, { value: amount })
      await expect(receipt).to.emit(vault, 'Transfer')
      await expect(receipt).to.emit(vault, 'Deposit')
      await expect(receipt).to.emit(vault, 'StateUpdated')
      await snapshotGasCost(receipt)
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
