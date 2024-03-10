import { ethers } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { ERC20Mock, GnoBlocklistVault, Keeper, OsTokenVaultController } from '../../typechain-types'
import { collateralizeGnoVault, depositGno, gnoVaultFixture } from '../shared/gnoFixtures'
import { expect } from '../shared/expect'
import { ZERO_ADDRESS } from '../shared/constants'
import snapshotGasCost from '../shared/snapshotGasCost'
import keccak256 from 'keccak256'
import { extractDepositShares } from '../shared/utils'

describe('GnoBlocklistVault', () => {
  const capacity = ethers.parseEther('1000')
  const feePercent = 1000
  const referrer = ZERO_ADDRESS
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  let sender: Wallet, admin: Wallet, other: Wallet, blocklistManager: Wallet, receiver: Wallet
  let vault: GnoBlocklistVault,
    keeper: Keeper,
    validatorsRegistry: Contract,
    osTokenVaultController: OsTokenVaultController,
    gnoToken: ERC20Mock

  beforeEach('deploy fixtures', async () => {
    ;[sender, receiver, admin, other, blocklistManager] = await (ethers as any).getSigners()
    const fixture = await loadFixture(gnoVaultFixture)
    vault = await fixture.createGnoBlocklistVault(admin, {
      capacity,
      feePercent,
      metadataIpfsHash,
    })
    keeper = fixture.keeper
    validatorsRegistry = fixture.validatorsRegistry
    osTokenVaultController = fixture.osTokenVaultController
    gnoToken = fixture.gnoToken
  })

  it('has id', async () => {
    expect(await vault.vaultId()).to.eq(`0x${keccak256('GnoBlocklistVault').toString('hex')}`)
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

  describe('deposit', () => {
    const assets = ethers.parseEther('1')

    beforeEach(async () => {
      await vault.connect(admin).setBlocklistManager(blocklistManager.address)
    })

    it('cannot be called by blocked sender', async () => {
      await vault.connect(blocklistManager).updateBlocklist(other.address, true)
      await expect(
        depositGno(vault, gnoToken, assets, other, receiver, referrer)
      ).to.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('cannot set receiver to blocked user', async () => {
      await vault.connect(blocklistManager).updateBlocklist(other.address, true)
      await expect(
        depositGno(vault, gnoToken, assets, sender, other, referrer)
      ).to.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('can be called by not blocked user', async () => {
      const receipt = await depositGno(vault, gnoToken, assets, sender, receiver, referrer)
      const shares = await extractDepositShares(receipt)

      await expect(receipt)
        .to.emit(vault, 'Deposited')
        .withArgs(sender.address, receiver.address, assets, shares, referrer)
      await snapshotGasCost(receipt)
    })
  })

  describe('mint osToken', () => {
    const assets = ethers.parseEther('1')
    let osTokenShares: bigint

    beforeEach(async () => {
      await collateralizeGnoVault(vault, gnoToken, keeper, validatorsRegistry, admin)
      await depositGno(vault, gnoToken, assets, sender, sender, referrer)
      osTokenShares = await osTokenVaultController.convertToShares(assets / 2n)
    })

    it('cannot mint from blocked user', async () => {
      await vault.connect(admin).updateBlocklist(sender.address, true)
      await expect(
        vault.connect(sender).mintOsToken(sender.address, osTokenShares, ZERO_ADDRESS)
      ).to.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('can mint from not blocked user', async () => {
      const tx = await vault
        .connect(sender)
        .mintOsToken(sender.address, osTokenShares, ZERO_ADDRESS)
      await expect(tx).to.emit(vault, 'OsTokenMinted')
      await snapshotGasCost(tx)
    })
  })
})
