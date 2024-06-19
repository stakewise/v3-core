import { ethers } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  EthVault,
  EthVaultMock,
  IKeeperRewards,
  Keeper,
  SharedMevEscrow,
  DepositDataRegistry,
} from '../typechain-types'
import { ThenArg } from '../helpers/types'
import snapshotGasCost from './shared/snapshotGasCost'
import { createDepositorMock, ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { PANIC_CODES, SECURITY_DEPOSIT, ZERO_ADDRESS } from './shared/constants'
import { collateralizeEthVault, getRewardsRootProof, updateRewards } from './shared/rewards'
import { setBalance } from './shared/utils'
import { registerEthValidator } from './shared/validators'

const ether = ethers.parseEther('1')

describe('EthVault - deposit', () => {
  const capacity = ethers.parseEther('1000')
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  const referrer = '0x' + '1'.repeat(40)
  let sender: Wallet, receiver: Wallet, admin: Wallet, other: Wallet
  let vault: EthVault,
    keeper: Keeper,
    mevEscrow: SharedMevEscrow,
    validatorsRegistry: Contract,
    depositDataRegistry: DepositDataRegistry

  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVault']
  let createVaultMock: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVaultMock']

  beforeEach('deploy fixtures', async () => {
    ;[sender, receiver, admin, other] = (await (ethers as any).getSigners()).slice(1, 5)
    ;({
      createEthVault: createVault,
      createEthVaultMock: createVaultMock,
      keeper,
      validatorsRegistry,
      sharedMevEscrow: mevEscrow,
      depositDataRegistry,
    } = await loadFixture(ethVaultFixture))
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

  it('fails to deposit to zero address', async () => {
    await expect(
      vault.connect(sender).deposit(ZERO_ADDRESS, referrer, { value: ethers.parseEther('999') })
    ).to.be.revertedWithCustomError(vault, 'ZeroAddress')
  })

  describe('empty vault: no assets & no shares', () => {
    it('status', async () => {
      expect(await vault.totalAssets()).to.equal(SECURITY_DEPOSIT)
      expect(await vault.totalShares()).to.equal(SECURITY_DEPOSIT)
    })

    it('deposit', async () => {
      const amount = ether
      expect(await vault.convertToShares(amount)).to.eq(amount)
      const receipt = await vault
        .connect(sender)
        .deposit(receiver.address, referrer, { value: amount })
      expect(await vault.getShares(receiver.address)).to.eq(amount)

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
      ).to.be.revertedWithPanic(PANIC_CODES.DIVISION_BY_ZERO)
    })
  })

  describe('full vault: assets & shares', () => {
    beforeEach(async () => {
      await vault
        .connect(other)
        .deposit(other.address, referrer, { value: ethers.parseEther('10') })
    })

    it('status', async () => {
      expect(await vault.totalAssets()).to.eq(ethers.parseEther('10') + SECURITY_DEPOSIT)
    })

    it('fails with exceeded capacity', async () => {
      await expect(
        vault
          .connect(sender)
          .deposit(receiver.address, referrer, { value: ethers.parseEther('999') })
      ).to.be.revertedWithCustomError(vault, 'CapacityExceeded')
    })

    it('fails when not harvested', async () => {
      await collateralizeEthVault(vault, keeper, depositDataRegistry, admin, validatorsRegistry)
      await updateRewards(keeper, [
        {
          reward: ethers.parseEther('5'),
          unlockedMevReward: 0n,
          vault: await vault.getAddress(),
        },
      ])
      await updateRewards(keeper, [
        {
          reward: ethers.parseEther('10'),
          unlockedMevReward: 0n,
          vault: await vault.getAddress(),
        },
      ])
      await expect(
        vault
          .connect(sender)
          .deposit(receiver.address, referrer, { value: ethers.parseEther('10') })
      ).to.be.revertedWithCustomError(vault, 'NotHarvested')
    })

    it('update state and deposit', async () => {
      await vault
        .connect(other)
        .deposit(other.address, referrer, { value: ethers.parseEther('32') })
      await registerEthValidator(vault, keeper, depositDataRegistry, admin, validatorsRegistry)
      await vault.connect(other).enterExitQueue(ethers.parseEther('32'), other.address)

      let vaultReward = ethers.parseEther('10')
      await updateRewards(keeper, [
        {
          reward: vaultReward,
          unlockedMevReward: vaultReward,
          vault: await vault.getAddress(),
        },
      ])

      vaultReward = vaultReward + ethers.parseEther('1')
      const tree = await updateRewards(keeper, [
        {
          reward: vaultReward,
          unlockedMevReward: vaultReward,
          vault: await vault.getAddress(),
        },
      ])

      const harvestParams: IKeeperRewards.HarvestParamsStruct = {
        rewardsRoot: tree.root,
        reward: vaultReward,
        unlockedMevReward: vaultReward,
        proof: getRewardsRootProof(tree, {
          vault: await vault.getAddress(),
          unlockedMevReward: vaultReward,
          reward: vaultReward,
        }),
      }
      await setBalance(await mevEscrow.getAddress(), vaultReward)
      await setBalance(await vault.getAddress(), ethers.parseEther('5'))

      const amount = ethers.parseEther('100')
      const receipt = await vault
        .connect(sender)
        .updateStateAndDeposit(receiver.address, referrer, harvestParams, { value: amount })
      await expect(receipt).to.emit(vault, 'Deposited')
      await expect(receipt).to.emit(keeper, 'Harvested')
      await expect(receipt).to.emit(mevEscrow, 'Harvested')
      await snapshotGasCost(receipt)
    })

    it('deposit', async () => {
      const amount = ethers.parseEther('100')
      const expectedShares = ethers.parseEther('100')
      expect(await vault.convertToShares(amount)).to.eq(expectedShares)

      const receipt = await vault
        .connect(sender)
        .deposit(receiver.address, referrer, { value: amount })
      expect(await vault.getShares(receiver.address)).to.eq(expectedShares)

      await expect(receipt)
        .to.emit(vault, 'Deposited')
        .withArgs(sender.address, receiver.address, amount, expectedShares, referrer)
      await snapshotGasCost(receipt)
    })

    it('deposit through receive fallback function', async () => {
      const depositorMock = await createDepositorMock(vault)
      const depositorMockAddress = await depositorMock.getAddress()
      const amount = ethers.parseEther('100')
      const expectedShares = ethers.parseEther('100')
      expect(await vault.convertToShares(amount)).to.eq(expectedShares)

      const receipt = await depositorMock.connect(sender).depositToVault({ value: amount })
      expect(await vault.getShares(depositorMockAddress)).to.eq(expectedShares)

      await expect(receipt)
        .to.emit(vault, 'Deposited')
        .withArgs(depositorMockAddress, depositorMockAddress, amount, expectedShares, ZERO_ADDRESS)
      await snapshotGasCost(receipt)
    })
  })
})
