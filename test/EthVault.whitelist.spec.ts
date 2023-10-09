import { ethers } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { EthPrivVault, Keeper, IKeeperRewards } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import { createDepositorMock, ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { ZERO_ADDRESS } from './shared/constants'
import snapshotGasCost from './shared/snapshotGasCost'
import { collateralizeEthVault, getRewardsRootProof, updateRewards } from './shared/rewards'

describe('EthVault - whitelist', () => {
  const capacity = ethers.parseEther('1000')
  const feePercent = 1000
  const referrer = ZERO_ADDRESS
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  let sender: Wallet, whitelister: Wallet, admin: Wallet, other: Wallet
  let vault: EthPrivVault, keeper: Keeper, validatorsRegistry: Contract

  let createPrivateVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthPrivVault']

  before('create fixture loader', async () => {
    ;[sender, whitelister, admin, other] = (await (ethers as any).getSigners()).slice(1, 5)
  })

  beforeEach('deploy fixtures', async () => {
    ;({
      createEthPrivVault: createPrivateVault,
      keeper,
      validatorsRegistry,
    } = await loadFixture(ethVaultFixture))
    vault = await createPrivateVault(admin, {
      capacity,
      feePercent,
      metadataIpfsHash,
    })
  })

  describe('set whitelister', () => {
    it('cannot be called by not admin', async () => {
      await expect(
        vault.connect(other).setWhitelister(whitelister.address)
      ).to.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('admin can update whitelister', async () => {
      const tx = await vault.connect(admin).setWhitelister(whitelister.address)
      await expect(tx)
        .to.emit(vault, 'WhitelisterUpdated')
        .withArgs(admin.address, whitelister.address)
      expect(await vault.whitelister()).to.be.eq(whitelister.address)
      await snapshotGasCost(tx)
    })
  })

  describe('whitelist', () => {
    beforeEach(async () => {
      await vault.connect(admin).setWhitelister(whitelister.address)
    })

    it('cannot be updated by not whitelister', async () => {
      await expect(
        vault.connect(other).updateWhitelist(sender.address, true)
      ).to.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('cannot be updated twice', async () => {
      await vault.connect(whitelister).updateWhitelist(sender.address, true)
      await expect(
        vault.connect(whitelister).updateWhitelist(sender.address, true)
      ).to.revertedWithCustomError(vault, 'WhitelistAlreadyUpdated')
    })

    it('can be updated by whitelister', async () => {
      // add to whitelist
      let tx = await vault.connect(whitelister).updateWhitelist(sender.address, true)
      await expect(tx)
        .to.emit(vault, 'WhitelistUpdated')
        .withArgs(whitelister.address, sender.address, true)
      expect(await vault.whitelistedAccounts(sender.address)).to.be.eq(true)
      await snapshotGasCost(tx)

      // remove from whitelist
      tx = await vault.connect(whitelister).updateWhitelist(sender.address, false)
      await expect(tx)
        .to.emit(vault, 'WhitelistUpdated')
        .withArgs(whitelister.address, sender.address, false)
      expect(await vault.whitelistedAccounts(sender.address)).to.be.eq(false)
      await snapshotGasCost(tx)
    })
  })

  describe('deposit', () => {
    const amount = ethers.parseEther('1')

    beforeEach(async () => {
      await vault.connect(admin).updateWhitelist(sender.address, true)
    })

    it('cannot be called by not whitelisted sender', async () => {
      await expect(
        vault.connect(other).deposit(other.address, referrer, { value: amount })
      ).to.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('cannot update state and call', async () => {
      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
      const vaultReward = ethers.parseEther('1')
      const tree = await updateRewards(keeper, [
        { reward: vaultReward, unlockedMevReward: 0n, vault: await vault.getAddress() },
      ])

      const harvestParams: IKeeperRewards.HarvestParamsStruct = {
        rewardsRoot: tree.root,
        reward: vaultReward,
        unlockedMevReward: 0n,
        proof: getRewardsRootProof(tree, {
          vault: await vault.getAddress(),
          unlockedMevReward: 0n,
          reward: vaultReward,
        }),
      }
      await expect(
        vault
          .connect(other)
          .updateStateAndDeposit(other.address, referrer, harvestParams, { value: amount })
      ).to.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('cannot set receiver to not whitelisted user', async () => {
      await expect(
        vault.connect(other).deposit(other.address, referrer, { value: amount })
      ).to.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('can be called by whitelisted user', async () => {
      const receipt = await vault
        .connect(sender)
        .deposit(sender.address, referrer, { value: amount })
      expect(await vault.getShares(sender.address)).to.eq(amount)

      await expect(receipt)
        .to.emit(vault, 'Deposited')
        .withArgs(sender.address, sender.address, amount, amount, referrer)
      await snapshotGasCost(receipt)
    })

    it('deposit through receive fallback cannot be called by not whitelisted sender', async () => {
      const depositorMock = await createDepositorMock(vault)
      const amount = ethers.parseEther('100')
      const expectedShares = ethers.parseEther('100')
      expect(await vault.convertToShares(amount)).to.eq(expectedShares)
      await expect(
        depositorMock.connect(sender).depositToVault({ value: amount })
      ).to.revertedWithCustomError(depositorMock, 'DepositFailed')
    })

    it('deposit through receive fallback can be called by whitelisted sender', async () => {
      const depositorMock = await createDepositorMock(vault)
      const depositorMockAddress = await depositorMock.getAddress()
      await vault.connect(admin).updateWhitelist(depositorMockAddress, true)

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
