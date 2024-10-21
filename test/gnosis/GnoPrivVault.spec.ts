import { ethers } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  ERC20Mock,
  GnoPrivVault,
  Keeper,
  OsTokenVaultController,
  DepositDataRegistry,
} from '../../typechain-types'
import { collateralizeGnoVault, depositGno, gnoVaultFixture } from '../shared/gnoFixtures'
import { expect } from '../shared/expect'
import { ZERO_ADDRESS } from '../shared/constants'
import snapshotGasCost from '../shared/snapshotGasCost'
import keccak256 from 'keccak256'
import { extractDepositShares } from '../shared/utils'

describe('GnoPrivVault', () => {
  const capacity = ethers.parseEther('1000')
  const feePercent = 1000
  const referrer = ZERO_ADDRESS
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  let sender: Wallet, admin: Wallet, other: Wallet, whitelister: Wallet, receiver: Wallet
  let vault: GnoPrivVault,
    keeper: Keeper,
    validatorsRegistry: Contract,
    osTokenVaultController: OsTokenVaultController,
    gnoToken: ERC20Mock,
    depositDataRegistry: DepositDataRegistry

  beforeEach('deploy fixtures', async () => {
    ;[sender, receiver, admin, other, whitelister] = await (ethers as any).getSigners()
    const fixture = await loadFixture(gnoVaultFixture)
    vault = await fixture.createGnoPrivVault(admin, {
      capacity,
      feePercent,
      metadataIpfsHash,
    })
    keeper = fixture.keeper
    validatorsRegistry = fixture.validatorsRegistry
    osTokenVaultController = fixture.osTokenVaultController
    gnoToken = fixture.gnoToken
    depositDataRegistry = fixture.depositDataRegistry
  })

  it('has id', async () => {
    expect(await vault.vaultId()).to.eq(`0x${keccak256('GnoPrivVault').toString('hex')}`)
  })

  it('has version', async () => {
    expect(await vault.version()).to.eq(3)
  })

  it('cannot initialize twice', async () => {
    await expect(vault.connect(other).initialize('0x')).revertedWithCustomError(
      vault,
      'InvalidInitialization'
    )
  })

  describe('deposit', () => {
    const amount = ethers.parseEther('1')

    beforeEach(async () => {
      await vault.connect(admin).setWhitelister(whitelister.address)
      await vault.connect(whitelister).updateWhitelist(sender.address, true)
    })

    it('cannot be called by not whitelisted sender', async () => {
      await expect(
        depositGno(vault, gnoToken, amount, receiver, sender, referrer)
      ).to.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('cannot set receiver to not whitelisted user', async () => {
      await expect(
        depositGno(vault, gnoToken, amount, sender, receiver, referrer)
      ).to.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('can be called by whitelisted user', async () => {
      const receipt = await depositGno(vault, gnoToken, amount, sender, sender, referrer)
      const shares = await extractDepositShares(receipt)

      await expect(receipt)
        .to.emit(vault, 'Deposited')
        .withArgs(sender.address, sender.address, amount, shares, referrer)
      await snapshotGasCost(receipt)
    })
  })

  describe('mint osToken', () => {
    const assets = ethers.parseEther('1')
    let osTokenShares: bigint

    beforeEach(async () => {
      await vault.connect(admin).updateWhitelist(await admin.getAddress(), true)
      await collateralizeGnoVault(
        vault,
        gnoToken,
        keeper,
        depositDataRegistry,
        admin,
        validatorsRegistry
      )
      await vault.connect(admin).updateWhitelist(sender.address, true)
      await depositGno(vault, gnoToken, assets, sender, sender, referrer)
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
})
