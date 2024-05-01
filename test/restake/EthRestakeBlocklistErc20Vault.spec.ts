import { ethers } from 'hardhat'
import { Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { EthRestakeBlocklistErc20Vault } from '../../typechain-types'
import { ethRestakeVaultFixture } from '../shared/restakeFixtures'
import { expect } from '../shared/expect'
import { ZERO_ADDRESS } from '../shared/constants'
import snapshotGasCost from '../shared/snapshotGasCost'
import keccak256 from 'keccak256'
import { extractDepositShares } from '../shared/utils'
import { createDepositorMock } from '../shared/fixtures'

describe('EthRestakeBlocklistErc20Vault', () => {
  const name = 'SW Vault'
  const symbol = 'SW-1'
  const capacity = ethers.parseEther('1000')
  const feePercent = 1000
  const referrer = ZERO_ADDRESS
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  let sender: Wallet, admin: Wallet, other: Wallet, blocklistManager: Wallet, receiver: Wallet
  let vault: EthRestakeBlocklistErc20Vault

  beforeEach('deploy fixtures', async () => {
    ;[sender, receiver, admin, other, blocklistManager] = await (ethers as any).getSigners()
    const fixture = await loadFixture(ethRestakeVaultFixture)
    vault = await fixture.createEthRestakeBlocklistErc20Vault(admin, {
      name,
      symbol,
      capacity,
      feePercent,
      metadataIpfsHash,
    })
  })

  it('has id', async () => {
    expect(await vault.vaultId()).to.eq(
      `0x${keccak256('EthRestakeBlocklistErc20Vault').toString('hex')}`
    )
  })

  it('has version', async () => {
    expect(await vault.version()).to.eq(2)
  })

  it('cannot initialize twice', async () => {
    await expect(vault.connect(other).initialize('0x')).revertedWithCustomError(
      vault,
      'InvalidInitialization'
    )
  })

  describe('transfer', () => {
    const amount = ethers.parseEther('1')

    beforeEach(async () => {
      await vault.connect(admin).setBlocklistManager(blocklistManager.address)
      vault.connect(sender).deposit(receiver.address, ZERO_ADDRESS, { value: amount })
    })

    it('cannot transfer to blocked user', async () => {
      await vault.connect(blocklistManager).updateBlocklist(other.address, true)
      await expect(
        vault.connect(sender).transfer(other.address, amount)
      ).to.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('cannot transfer from blocked user', async () => {
      await vault.connect(blocklistManager).updateBlocklist(sender.address, true)
      await expect(
        vault.connect(sender).transfer(other.address, amount)
      ).to.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('can transfer', async () => {
      const receipt = await vault.connect(receiver).transfer(other.address, amount)
      expect(await vault.balanceOf(receiver.address)).to.eq(0)
      expect(await vault.balanceOf(other.address)).to.eq(amount)

      await expect(receipt)
        .to.emit(vault, 'Transfer')
        .withArgs(receiver.address, other.address, amount)
      await snapshotGasCost(receipt)
    })
  })

  describe('deposit', () => {
    const assets = ethers.parseEther('1')

    beforeEach(async () => {
      await vault.connect(admin).setBlocklistManager(blocklistManager.address)
    })

    it('cannot be called by blocked sender', async () => {
      await vault.connect(blocklistManager).updateBlocklist(other.address, true)
      await expect(
        vault.connect(other).deposit(sender.address, ZERO_ADDRESS, { value: assets })
      ).to.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('cannot set receiver to blocked user', async () => {
      await vault.connect(blocklistManager).updateBlocklist(other.address, true)
      await expect(
        vault.connect(sender).deposit(other.address, ZERO_ADDRESS, { value: assets })
      ).to.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('deposit through receive fallback cannot be called by blocked sender', async () => {
      const depositorMock = await createDepositorMock(vault)
      const amount = ethers.parseEther('100')
      const expectedShares = await vault.convertToShares(amount)
      expect(await vault.convertToShares(amount)).to.eq(expectedShares)
      await vault.connect(blocklistManager).updateBlocklist(await depositorMock.getAddress(), true)
      await expect(
        depositorMock.connect(sender).depositToVault({ value: amount })
      ).to.revertedWithCustomError(depositorMock, 'DepositFailed')
    })

    it('deposit through receive fallback can be called by not blocked sender', async () => {
      const depositorMock = await createDepositorMock(vault)
      const depositorMockAddress = await depositorMock.getAddress()

      const amount = ethers.parseEther('100')
      const expectedShares = await vault.convertToShares(amount)
      expect(await vault.convertToShares(amount)).to.eq(expectedShares)
      const receipt = await depositorMock.connect(sender).depositToVault({ value: amount })
      expect(await vault.getShares(depositorMockAddress)).to.eq(expectedShares)

      await expect(receipt)
        .to.emit(vault, 'Deposited')
        .withArgs(depositorMockAddress, depositorMockAddress, amount, expectedShares, ZERO_ADDRESS)
      await snapshotGasCost(receipt)
    })

    it('can be called by not blocked user', async () => {
      const receipt = await vault
        .connect(sender)
        .deposit(receiver.address, ZERO_ADDRESS, { value: assets })
      const shares = await extractDepositShares(receipt)

      await expect(receipt)
        .to.emit(vault, 'Deposited')
        .withArgs(sender.address, receiver.address, assets, shares, referrer)
      await snapshotGasCost(receipt)
    })
  })
})
