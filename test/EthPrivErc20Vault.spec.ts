import { ethers } from 'hardhat'
import { Contract, parseEther, Signer, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { EthPrivErc20Vault, IKeeperRewards, Keeper } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import { createDepositorMock, ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { ZERO_ADDRESS } from './shared/constants'
import snapshotGasCost from './shared/snapshotGasCost'
import { collateralizeEthVault, getRewardsRootProof, updateRewards } from './shared/rewards'
import keccak256 from 'keccak256'

describe('EthPrivErc20Vault', () => {
  const capacity = ethers.parseEther('1000')
  const name = 'SW ETH Vault'
  const symbol = 'SW-ETH-1'
  const feePercent = 1000
  const referrer = ZERO_ADDRESS
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  let sender: Wallet, admin: Signer, other: Wallet, whitelister: Wallet
  let vault: EthPrivErc20Vault, keeper: Keeper, validatorsRegistry: Contract

  let createPrivateVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthPrivErc20Vault']

  beforeEach('deploy fixtures', async () => {
    ;[sender, admin, other, whitelister] = await (ethers as any).getSigners()
    ;({
      createEthPrivErc20Vault: createPrivateVault,
      keeper,
      validatorsRegistry,
    } = await loadFixture(ethVaultFixture))
    vault = await createPrivateVault(admin, {
      capacity,
      name,
      symbol,
      feePercent,
      metadataIpfsHash,
    })
    admin = await ethers.getImpersonatedSigner(await vault.admin())
  })

  it('has id', async () => {
    expect(await vault.vaultId()).to.eq(`0x${keccak256('EthPrivErc20Vault').toString('hex')}`)
  })

  it('has version', async () => {
    expect(await vault.version()).to.eq(2)
  })

  describe('deposit', () => {
    const amount = ethers.parseEther('1')

    beforeEach(async () => {
      await vault.connect(admin).updateWhitelist(await admin.getAddress(), true)
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
      expect(await vault.balanceOf(sender.address)).to.eq(amount)

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
      await vault.connect(admin).updateWhitelist(await depositorMock.getAddress(), true)

      const amount = ethers.parseEther('100')
      const expectedShares = ethers.parseEther('100')
      expect(await vault.convertToShares(amount)).to.eq(expectedShares)
      const receipt = await depositorMock.connect(sender).depositToVault({ value: amount })
      expect(await vault.balanceOf(await depositorMock.getAddress())).to.eq(expectedShares)

      await expect(receipt)
        .to.emit(vault, 'Deposited')
        .withArgs(
          await depositorMock.getAddress(),
          await depositorMock.getAddress(),
          amount,
          expectedShares,
          ZERO_ADDRESS
        )
      await snapshotGasCost(receipt)
    })
  })

  describe('transfer', () => {
    const amount = ethers.parseEther('1')

    beforeEach(async () => {
      await vault.connect(admin).updateWhitelist(sender.address, true)
      await vault.connect(sender).deposit(sender.address, referrer, { value: amount })
    })

    it('cannot transfer to not whitelisted user', async () => {
      await expect(
        vault.connect(sender).transfer(other.address, amount)
      ).to.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('cannot transfer from not whitelisted user', async () => {
      await vault.connect(admin).updateWhitelist(other.address, true)
      await vault.connect(sender).transfer(other.address, amount)
      await vault.connect(admin).updateWhitelist(sender.address, false)
      await expect(
        vault.connect(other).transfer(sender.address, amount)
      ).to.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('can transfer to whitelisted user', async () => {
      await vault.connect(admin).updateWhitelist(other.address, true)
      const receipt = await vault.connect(sender).transfer(other.address, amount)
      expect(await vault.balanceOf(sender.address)).to.eq(0)
      expect(await vault.balanceOf(other.address)).to.eq(amount)

      await expect(receipt)
        .to.emit(vault, 'Transfer')
        .withArgs(sender.address, other.address, amount)
      await snapshotGasCost(receipt)
    })
  })

  describe('ejecting user', () => {
    const senderAssets = parseEther('1')

    beforeEach(async () => {
      await vault.connect(admin).updateWhitelist(sender.address, true)
      await vault.connect(admin).updateWhitelist(await admin.getAddress(), true)
      await vault.connect(sender).deposit(sender.address, referrer, { value: senderAssets })
      await vault.connect(admin).setWhitelister(whitelister.address)
    })

    it('fails for not whitelister', async () => {
      await expect(vault.connect(other).ejectUser(sender.address)).to.revertedWithCustomError(
        vault,
        'AccessDenied'
      )
    })

    it('fails when not harvested', async () => {
      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
      await vault.connect(sender).mintOsToken(sender.address, senderAssets / 2n, ZERO_ADDRESS)
      await updateRewards(keeper, [
        {
          vault: await vault.getAddress(),
          reward: ethers.parseEther('1'),
          unlockedMevReward: ethers.parseEther('0'),
        },
      ])
      await updateRewards(keeper, [
        {
          vault: await vault.getAddress(),
          reward: ethers.parseEther('1.2'),
          unlockedMevReward: ethers.parseEther('0'),
        },
      ])
      await expect(vault.connect(whitelister).ejectUser(sender.address)).to.revertedWithCustomError(
        vault,
        'NotHarvested'
      )
    })

    it('does not fail for user with no vault shares', async () => {
      await vault.connect(whitelister).updateWhitelist(other.address, true)

      expect(await vault.getShares(other.address)).to.eq(0)
      expect(await vault.whitelistedAccounts(other.address)).to.eq(true)

      const tx = await vault.connect(whitelister).ejectUser(other.address)
      await expect(tx)
        .to.emit(vault, 'WhitelistUpdated')
        .withArgs(whitelister.address, other.address, false)
      expect(await vault.whitelistedAccounts(other.address)).to.eq(false)
      await snapshotGasCost(tx)
    })

    it('does not fail for user with no osToken shares', async () => {
      expect(await vault.osTokenPositions(sender.address)).to.eq(0)
      expect(await vault.whitelistedAccounts(sender.address)).to.eq(true)
      expect(await vault.getShares(sender.address)).to.eq(senderAssets)

      const tx = await vault.connect(whitelister).ejectUser(sender.address)
      await expect(tx)
        .to.emit(vault, 'WhitelistUpdated')
        .withArgs(whitelister.address, sender.address, false)
      await expect(tx)
        .to.emit(vault, 'ExitQueueEntered')
        .withArgs(sender.address, sender.address, 0n, senderAssets)

      expect(await vault.whitelistedAccounts(sender.address)).to.eq(false)
      expect(await vault.getShares(sender.address)).to.eq(0)
      await snapshotGasCost(tx)
    })

    it('whitelister can eject some of the user assets', async () => {
      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
      const osTokenShares = senderAssets / 2n
      const senderShares = await vault.getShares(sender.address)
      await vault.connect(sender).mintOsToken(sender.address, osTokenShares, ZERO_ADDRESS)

      expect(await vault.osTokenPositions(sender.address)).to.eq(osTokenShares)
      expect(await vault.whitelistedAccounts(sender.address)).to.eq(true)
      expect(await vault.getShares(sender.address)).to.eq(senderShares)

      const tx = await vault.connect(whitelister).ejectUser(sender.address)
      const ejectedShares = senderShares - (await vault.getShares(sender.address))
      expect(ejectedShares).to.be.lessThan(senderShares)

      const ejectedAssets = await vault.convertToAssets(ejectedShares)
      expect(ejectedAssets).to.be.lessThan(senderAssets)

      await expect(tx)
        .to.emit(vault, 'WhitelistUpdated')
        .withArgs(whitelister.address, sender.address, false)
      await expect(tx)
        .to.emit(vault, 'ExitQueueEntered')
        .withArgs(sender.address, sender.address, parseEther('32'), ejectedAssets)

      expect(await vault.whitelistedAccounts(sender.address)).to.eq(false)
      expect(await vault.getShares(sender.address)).to.eq(senderShares - ejectedShares)
      await snapshotGasCost(tx)
    })

    it('whitelister can eject all of the user assets', async () => {
      expect(await vault.osTokenPositions(sender.address)).to.eq(0)
      expect(await vault.whitelistedAccounts(sender.address)).to.eq(true)

      const tx = await vault.connect(whitelister).ejectUser(sender.address)
      await expect(tx)
        .to.emit(vault, 'WhitelistUpdated')
        .withArgs(whitelister.address, sender.address, false)
      await expect(tx)
        .to.emit(vault, 'ExitQueueEntered')
        .withArgs(sender.address, sender.address, 0n, senderAssets)

      expect(await vault.whitelistedAccounts(sender.address)).to.eq(false)
      expect(await vault.getShares(sender.address)).to.eq(0)
      await snapshotGasCost(tx)
    })
  })
})
