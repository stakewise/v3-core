import { ethers, waffle } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import { EthVault, EthVaultMock, IKeeperRewards, Keeper, SharedMevEscrow } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import snapshotGasCost from './shared/snapshotGasCost'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { PANIC_CODES, SECURITY_DEPOSIT, ZERO_ADDRESS } from './shared/constants'
import { getRewardsRootProof, updateRewards } from './shared/rewards'
import { registerEthValidator } from './shared/validators'
import { setBalance } from './shared/utils'

const createFixtureLoader = waffle.createFixtureLoader
const ether = parseEther('1')

describe('EthVault - deposit', () => {
  const capacity = parseEther('1000')
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  const referrer = '0x' + '1'.repeat(40)
  let dao: Wallet, sender: Wallet, receiver: Wallet, admin: Wallet, other: Wallet
  let vault: EthVault, keeper: Keeper, mevEscrow: SharedMevEscrow, validatorsRegistry: Contract

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVault']
  let createVaultMock: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVaultMock']

  before('create fixture loader', async () => {
    ;[dao, sender, receiver, admin, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([dao])
  })

  beforeEach('deploy fixtures', async () => {
    ;({
      createEthVault: createVault,
      createEthVaultMock: createVaultMock,
      keeper,
      validatorsRegistry,
      sharedMevEscrow: mevEscrow,
    } = await loadFixture(ethVaultFixture))
    vault = await createVault(admin, {
      capacity,
      feePercent,
      metadataIpfsHash,
    })
  })

  it('fails to deposit to zero address', async () => {
    await expect(
      vault.connect(sender).deposit(ZERO_ADDRESS, referrer, { value: parseEther('999') })
    ).to.be.revertedWith('ZeroAddress')
  })

  describe('empty vault: no assets & no shares', () => {
    it('status', async () => {
      expect(await vault.totalAssets()).to.equal(SECURITY_DEPOSIT)
      expect(await vault.totalSupply()).to.equal(SECURITY_DEPOSIT)
    })

    it('deposit', async () => {
      const amount = ether
      expect(await vault.convertToShares(amount)).to.eq(amount)
      const receipt = await vault
        .connect(sender)
        .deposit(receiver.address, referrer, { value: amount })
      expect(await vault.balanceOf(receiver.address)).to.eq(amount)

      await expect(receipt)
        .to.emit(vault, 'Deposited')
        .withArgs(sender.address, receiver.address, amount, amount, referrer)
      await snapshotGasCost(receipt)
    })
  })

  describe('partially empty vault: shares & no assets', () => {
    let ethVaultMock: EthVaultMock

    beforeEach(async () => {
      ethVaultMock = await createVaultMock(admin, {
        capacity,
        feePercent,
        metadataIpfsHash,
      })
      await ethVaultMock._setTotalAssets(0)
    })

    it('status', async () => {
      expect(await ethVaultMock.totalAssets()).to.eq(0)
    })

    it('deposit', async () => {
      await expect(
        ethVaultMock.connect(sender).deposit(receiver.address, referrer, { value: ether })
      ).to.be.revertedWith(PANIC_CODES.DIVISION_BY_ZERO)
    })
  })

  describe('full vault: assets & shares', () => {
    beforeEach(async () => {
      await vault.connect(other).deposit(other.address, referrer, { value: parseEther('10') })
    })

    it('status', async () => {
      expect(await vault.totalAssets()).to.eq(parseEther('10').add(SECURITY_DEPOSIT))
    })

    it('fails with exceeded capacity', async () => {
      await expect(
        vault.connect(sender).deposit(receiver.address, referrer, { value: parseEther('999') })
      ).to.be.revertedWith('CapacityExceeded')
    })

    it('fails when not harvested', async () => {
      await vault.connect(other).deposit(other.address, referrer, { value: parseEther('32') })
      await registerEthValidator(vault, keeper, validatorsRegistry, admin)
      await updateRewards(keeper, [
        {
          reward: parseEther('5'),
          unlockedMevReward: 0,
          vault: vault.address,
        },
      ])
      await updateRewards(keeper, [
        {
          reward: parseEther('10'),
          unlockedMevReward: 0,
          vault: vault.address,
        },
      ])
      await expect(
        vault.connect(sender).deposit(receiver.address, referrer, { value: parseEther('10') })
      ).to.be.revertedWith('NotHarvested')
    })

    it('update state and deposit', async () => {
      await vault.connect(other).deposit(other.address, referrer, { value: parseEther('32') })
      await registerEthValidator(vault, keeper, validatorsRegistry, admin)

      let vaultReward = parseEther('10')
      await updateRewards(keeper, [
        {
          reward: vaultReward,
          unlockedMevReward: vaultReward,
          vault: vault.address,
        },
      ])

      vaultReward = vaultReward.add(parseEther('1'))
      const tree = await updateRewards(keeper, [
        {
          reward: vaultReward,
          unlockedMevReward: vaultReward,
          vault: vault.address,
        },
      ])

      const harvestParams: IKeeperRewards.HarvestParamsStruct = {
        rewardsRoot: tree.root,
        reward: vaultReward,
        unlockedMevReward: vaultReward,
        proof: getRewardsRootProof(tree, {
          vault: vault.address,
          unlockedMevReward: vaultReward,
          reward: vaultReward,
        }),
      }
      await setBalance(mevEscrow.address, vaultReward)
      await setBalance(await vault.address, parseEther('5'))
      await vault.connect(other).enterExitQueue(parseEther('32'), other.address)

      const amount = parseEther('100')
      const receipt = await vault
        .connect(sender)
        .updateStateAndDeposit(receiver.address, referrer, harvestParams, { value: amount })
      await expect(receipt).to.emit(vault, 'Deposited')
      await expect(receipt).to.emit(keeper, 'Harvested')
      await expect(receipt).to.emit(mevEscrow, 'Harvested')
      await expect(receipt).to.emit(vault, 'CheckpointCreated')
      await snapshotGasCost(receipt)
    })

    it('deposit', async () => {
      const amount = parseEther('100')
      const expectedShares = parseEther('100')
      expect(await vault.convertToShares(amount)).to.eq(expectedShares)

      const receipt = await vault
        .connect(sender)
        .deposit(receiver.address, referrer, { value: amount })
      expect(await vault.balanceOf(receiver.address)).to.eq(expectedShares)

      await expect(receipt)
        .to.emit(vault, 'Deposited')
        .withArgs(sender.address, receiver.address, amount, expectedShares, referrer)
      await snapshotGasCost(receipt)
    })

    it('deposit through receive fallback function', async () => {
      const depositorMockFactory = await ethers.getContractFactory('DepositorMock')
      const depositorMock = await depositorMockFactory.deploy(vault.address)

      const amount = parseEther('100')
      const expectedShares = parseEther('100')
      expect(await vault.convertToShares(amount)).to.eq(expectedShares)

      const receipt = await depositorMock.connect(sender).depositToVault({ value: amount })
      expect(await vault.balanceOf(depositorMock.address)).to.eq(expectedShares)

      await expect(receipt)
        .to.emit(vault, 'Deposited')
        .withArgs(
          depositorMock.address,
          depositorMock.address,
          amount,
          expectedShares,
          ZERO_ADDRESS
        )
      await snapshotGasCost(receipt)
    })
  })
})
