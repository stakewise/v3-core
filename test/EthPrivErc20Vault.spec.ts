import { ethers } from 'hardhat'
import { Contract, Signer, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  EthPrivErc20Vault,
  IKeeperRewards,
  Keeper,
  OsTokenVaultController,
  DepositDataRegistry,
} from '../typechain-types'
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
  let sender: Wallet, admin: Signer, other: Wallet
  let vault: EthPrivErc20Vault,
    keeper: Keeper,
    validatorsRegistry: Contract,
    osTokenVaultController: OsTokenVaultController,
    depositDataRegistry: DepositDataRegistry

  let createPrivateVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthPrivErc20Vault']

  beforeEach('deploy fixtures', async () => {
    ;[sender, admin, other] = await (ethers as any).getSigners()
    ;({
      createEthPrivErc20Vault: createPrivateVault,
      keeper,
      validatorsRegistry,
      osTokenVaultController,
      depositDataRegistry,
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
      await collateralizeEthVault(vault, keeper, depositDataRegistry, admin, validatorsRegistry)
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

  describe('mint osToken', () => {
    const assets = ethers.parseEther('1')
    let osTokenShares: bigint

    beforeEach(async () => {
      await vault.connect(admin).updateWhitelist(sender.address, true)
      await vault.connect(admin).updateWhitelist(await admin.getAddress(), true)
      await collateralizeEthVault(vault, keeper, depositDataRegistry, admin, validatorsRegistry)
      await vault.connect(sender).deposit(sender.address, referrer, { value: assets })
      osTokenShares = await osTokenVaultController.convertToShares(assets / 2n)
    })

    it('cannot mint from not whitelisted user', async () => {
      await vault.connect(admin).updateWhitelist(sender.address, false)
      await expect(
        vault.connect(sender).mintOsToken(sender.address, osTokenShares, ZERO_ADDRESS)
      ).to.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('can mint from whitelisted user', async () => {
      const tx = await vault
        .connect(sender)
        .mintOsToken(sender.address, osTokenShares, ZERO_ADDRESS)
      await expect(tx).to.emit(vault, 'OsTokenMinted')
      await snapshotGasCost(tx)
    })
  })
})
