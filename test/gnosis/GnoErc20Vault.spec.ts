import { ethers } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import keccak256 from 'keccak256'
import {
  ERC20Mock,
  GnoErc20Vault,
  Keeper,
  OsTokenVaultController,
  DepositDataRegistry,
} from '../../typechain-types'
import { collateralizeGnoVault, depositGno, gnoVaultFixture } from '../shared/gnoFixtures'
import { expect } from '../shared/expect'
import { ZERO_ADDRESS } from '../shared/constants'
import snapshotGasCost from '../shared/snapshotGasCost'
import { extractExitPositionTicket } from '../shared/utils'
import { getHarvestParams, updateRewards } from '../shared/rewards'

describe('GnoErc20Vault', () => {
  const name = 'SW GNO Vault'
  const symbol = 'SW-GNO-1'
  const capacity = ethers.parseEther('1000')
  const feePercent = 1000
  const referrer = ZERO_ADDRESS
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  let sender: Wallet, admin: Wallet, other: Wallet, receiver: Wallet
  let vault: GnoErc20Vault,
    keeper: Keeper,
    validatorsRegistry: Contract,
    osTokenVaultController: OsTokenVaultController,
    gnoToken: ERC20Mock,
    depositDataRegistry: DepositDataRegistry

  beforeEach('deploy fixtures', async () => {
    ;[sender, receiver, admin, other] = await (ethers as any).getSigners()
    const fixture = await loadFixture(gnoVaultFixture)
    vault = await fixture.createGnoErc20Vault(admin, {
      name,
      symbol,
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
    expect(await vault.vaultId()).to.eq(`0x${keccak256('GnoErc20Vault').toString('hex')}`)
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

  it('deposit emits transfer event', async () => {
    const amount = ethers.parseEther('100')
    const expectedShares = await vault.convertToShares(amount)
    const receipt = await depositGno(vault, gnoToken, amount, sender, receiver, referrer)
    expect(await vault.balanceOf(receiver.address)).to.eq(expectedShares)

    await expect(receipt)
      .to.emit(vault, 'Deposited')
      .withArgs(sender.address, receiver.address, amount, expectedShares, referrer)
    await expect(receipt)
      .to.emit(vault, 'Transfer')
      .withArgs(ZERO_ADDRESS, receiver.address, expectedShares)
    await snapshotGasCost(receipt)
  })

  it('enter exit queue emits transfer event', async () => {
    await collateralizeGnoVault(
      vault,
      gnoToken,
      keeper,
      depositDataRegistry,
      admin,
      validatorsRegistry
    )
    const queuedSharesBefore = await vault.queuedShares()
    const totalAssetsBefore = await vault.totalAssets()
    const totalSharesBefore = await vault.totalShares()

    const amount = ethers.parseEther('100')
    const shares = await vault.convertToShares(amount)
    await depositGno(vault, gnoToken, amount, sender, sender, referrer)
    expect(await vault.balanceOf(sender.address)).to.be.eq(shares)

    const receipt = await vault.connect(sender).enterExitQueue(shares, receiver.address)
    const positionTicket = await extractExitPositionTicket(receipt)
    await expect(receipt)
      .to.emit(vault, 'ExitQueueEntered')
      .withArgs(sender.address, receiver.address, positionTicket, shares)
    await expect(receipt)
      .to.emit(vault, 'Transfer')
      .withArgs(sender.address, await vault.getAddress(), shares)
    expect(await vault.queuedShares()).to.be.eq(queuedSharesBefore + shares)
    expect(await vault.totalAssets()).to.be.eq(totalAssetsBefore + amount)
    expect(await vault.totalSupply()).to.be.eq(totalSharesBefore + shares)
    expect(await vault.balanceOf(sender.address)).to.be.eq(0)

    await snapshotGasCost(receipt)
  })

  it('cannot transfer vault shares when unharvested and osToken minted', async () => {
    await collateralizeGnoVault(
      vault,
      gnoToken,
      keeper,
      depositDataRegistry,
      admin,
      validatorsRegistry
    )
    const assets = ethers.parseEther('1')
    const shares = await vault.convertToShares(assets)
    const osTokenShares = await osTokenVaultController.convertToShares(assets / 2n)

    await depositGno(vault, gnoToken, assets, sender, sender, referrer)
    await vault.connect(sender).mintOsToken(receiver.address, osTokenShares, ZERO_ADDRESS)

    await updateRewards(keeper, [
      getHarvestParams(await vault.getAddress(), ethers.parseEther('1'), ethers.parseEther('0')),
    ])
    await updateRewards(keeper, [
      getHarvestParams(await vault.getAddress(), ethers.parseEther('1.2'), ethers.parseEther('0')),
    ])
    await expect(
      vault.connect(sender).transfer(receiver.address, shares)
    ).to.be.revertedWithCustomError(vault, 'NotHarvested')
  })

  it('cannot transfer vault shares when LTV is violated', async () => {
    await collateralizeGnoVault(
      vault,
      gnoToken,
      keeper,
      depositDataRegistry,
      admin,
      validatorsRegistry
    )
    const assets = ethers.parseEther('2')
    const shares = await vault.convertToShares(assets)
    const osTokenShares = await osTokenVaultController.convertToShares(assets / 2n)

    await depositGno(vault, gnoToken, assets, sender, sender, referrer)
    await vault.connect(sender).mintOsToken(receiver.address, osTokenShares, ZERO_ADDRESS)
    await expect(
      vault.connect(sender).transfer(receiver.address, shares)
    ).to.be.revertedWithCustomError(vault, 'LowLtv')
    await vault.connect(sender).approve(receiver.address, shares)
    await expect(
      vault.connect(receiver).transferFrom(sender.address, receiver.address, shares)
    ).to.be.revertedWithCustomError(vault, 'LowLtv')
  })

  it('can transfer vault shares when LTV is not violated', async () => {
    await collateralizeGnoVault(
      vault,
      gnoToken,
      keeper,
      depositDataRegistry,
      admin,
      validatorsRegistry
    )
    const assets = ethers.parseEther('2')
    const osTokenShares = await osTokenVaultController.convertToShares(assets / 2n)
    const transferShares = await vault.convertToShares(ethers.parseEther('0.1'))

    await depositGno(vault, gnoToken, assets, sender, sender, referrer)
    await vault.connect(sender).mintOsToken(receiver.address, osTokenShares, ZERO_ADDRESS)
    await expect(vault.connect(sender).transfer(receiver.address, transferShares)).to.emit(
      vault,
      'Transfer'
    )
    await vault.connect(sender).approve(receiver.address, transferShares)
    await expect(
      vault.connect(receiver).transferFrom(sender.address, receiver.address, transferShares)
    ).to.emit(vault, 'Transfer')
  })
})
