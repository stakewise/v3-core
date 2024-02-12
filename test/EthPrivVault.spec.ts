import { ethers } from 'hardhat'
import { Contract, parseEther, Signer, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { EthPrivVault, Keeper, OsTokenVaultController } from '../typechain-types'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { ZERO_ADDRESS } from './shared/constants'
import snapshotGasCost from './shared/snapshotGasCost'
import { collateralizeEthVault, updateRewards } from './shared/rewards'
import keccak256 from 'keccak256'
import { extractDepositShares, extractExitPositionTicket } from './shared/utils'

describe('EthPrivVault', () => {
  const capacity = ethers.parseEther('1000')
  const feePercent = 1000
  const referrer = ZERO_ADDRESS
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  let sender: Wallet, admin: Signer, other: Wallet, whitelister: Wallet
  let vault: EthPrivVault,
    keeper: Keeper,
    validatorsRegistry: Contract,
    osTokenVaultController: OsTokenVaultController

  beforeEach('deploy fixtures', async () => {
    ;[sender, admin, other, whitelister] = await (ethers as any).getSigners()
    const fixture = await loadFixture(ethVaultFixture)
    vault = await fixture.createEthPrivVault(admin, {
      capacity,
      feePercent,
      metadataIpfsHash,
    })
    admin = await ethers.getImpersonatedSigner(await vault.admin())
    keeper = fixture.keeper
    validatorsRegistry = fixture.validatorsRegistry
    osTokenVaultController = fixture.osTokenVaultController
  })

  it('has id', async () => {
    expect(await vault.vaultId()).to.eq(`0x${keccak256('EthPrivVault').toString('hex')}`)
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

  describe('mint osToken', () => {
    const assets = ethers.parseEther('1')
    let osTokenShares: bigint

    beforeEach(async () => {
      await vault.connect(admin).updateWhitelist(await admin.getAddress(), true)
      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
      await vault.connect(admin).updateWhitelist(sender.address, true)
      await vault.connect(sender).deposit(sender.address, referrer, { value: assets })
      osTokenShares = await osTokenVaultController.convertToShares(assets / 2n)
    })

    it('cannot mint from not whitelisted user', async () => {
      await vault.connect(admin).updateWhitelist(sender.address, false)
      await expect(
        vault.connect(sender).mintOsToken(sender.address, osTokenShares, ZERO_ADDRESS)
      ).to.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('can mint from not whitelisted user', async () => {
      const tx = await vault
        .connect(sender)
        .mintOsToken(sender.address, osTokenShares, ZERO_ADDRESS)
      await expect(tx).to.emit(vault, 'OsTokenMinted')
      await snapshotGasCost(tx)
    })
  })

  describe('ejecting user', () => {
    const senderAssets = parseEther('1')
    let senderShares: bigint

    beforeEach(async () => {
      await vault.connect(admin).updateWhitelist(sender.address, true)
      await vault.connect(admin).updateWhitelist(await admin.getAddress(), true)
      await vault.connect(admin).setWhitelister(whitelister.address)
      const tx = await vault
        .connect(sender)
        .deposit(sender.address, referrer, { value: senderAssets })
      senderShares = await extractDepositShares(tx)
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
      expect(await vault.getShares(sender.address)).to.eq(senderShares)

      const tx = await vault.connect(whitelister).ejectUser(sender.address)
      const positionTicket = await extractExitPositionTicket(tx)
      await expect(tx)
        .to.emit(vault, 'WhitelistUpdated')
        .withArgs(whitelister.address, sender.address, false)
      await expect(tx)
        .to.emit(vault, 'ExitQueueEntered')
        .withArgs(sender.address, sender.address, positionTicket, senderAssets)

      expect(await vault.whitelistedAccounts(sender.address)).to.eq(false)
      expect(await vault.getShares(sender.address)).to.eq(0)
      await snapshotGasCost(tx)
    })

    it('whitelister can eject some of the user assets', async () => {
      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
      const osTokenShares = senderAssets / 2n
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
      await expect(tx).to.emit(vault, 'ExitQueueEntered')

      expect(await vault.whitelistedAccounts(sender.address)).to.eq(false)
      expect(await vault.getShares(sender.address)).to.eq(senderShares - ejectedShares)
      await snapshotGasCost(tx)
    })

    it('whitelister can eject all of the user assets', async () => {
      expect(await vault.osTokenPositions(sender.address)).to.eq(0)
      expect(await vault.whitelistedAccounts(sender.address)).to.eq(true)

      const tx = await vault.connect(whitelister).ejectUser(sender.address)
      const positionTicket = await extractExitPositionTicket(tx)
      await expect(tx)
        .to.emit(vault, 'WhitelistUpdated')
        .withArgs(whitelister.address, sender.address, false)
      await expect(tx)
        .to.emit(vault, 'ExitQueueEntered')
        .withArgs(sender.address, sender.address, positionTicket, senderAssets)

      expect(await vault.whitelistedAccounts(sender.address)).to.eq(false)
      expect(await vault.getShares(sender.address)).to.eq(0)
      await snapshotGasCost(tx)
    })
  })
})
