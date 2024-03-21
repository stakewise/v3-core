import { ethers } from 'hardhat'
import { Contract, Signer, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  EthPrivVault,
  Keeper,
  OsTokenVaultController,
  DepositDataManager,
} from '../typechain-types'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { ZERO_ADDRESS } from './shared/constants'
import snapshotGasCost from './shared/snapshotGasCost'
import { collateralizeEthVault } from './shared/rewards'
import keccak256 from 'keccak256'

describe('EthPrivVault', () => {
  const capacity = ethers.parseEther('1000')
  const feePercent = 1000
  const referrer = ZERO_ADDRESS
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  let sender: Wallet, admin: Signer, other: Wallet
  let vault: EthPrivVault,
    keeper: Keeper,
    validatorsRegistry: Contract,
    osTokenVaultController: OsTokenVaultController,
    depositDataManager: DepositDataManager

  beforeEach('deploy fixtures', async () => {
    ;[sender, admin, other] = await (ethers as any).getSigners()
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
    depositDataManager = fixture.depositDataManager
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
      await collateralizeEthVault(vault, keeper, depositDataManager, admin, validatorsRegistry)
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
})
