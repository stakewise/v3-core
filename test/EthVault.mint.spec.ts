import { ethers } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  EthVault,
  Keeper,
  OsToken,
  VaultsRegistry,
  OsTokenVaultController,
} from '../typechain-types'
import { ThenArg } from '../helpers/types'
import snapshotGasCost from './shared/snapshotGasCost'
import { createUnknownVaultMock, ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { ONE_DAY, ZERO_ADDRESS } from './shared/constants'
import { collateralizeEthVault, updateRewards } from './shared/rewards'
import { increaseTime } from './shared/utils'

describe('EthVault - mint', () => {
  const assets = ethers.parseEther('2')
  const osTokenShares = ethers.parseEther('1')
  const vaultParams = {
    capacity: ethers.parseEther('1000'),
    feePercent: 1000,
    metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u',
  }
  let dao: Wallet, sender: Wallet, receiver: Wallet, admin: Wallet
  let vault: EthVault,
    keeper: Keeper,
    vaultsRegistry: VaultsRegistry,
    osTokenVaultController: OsTokenVaultController,
    osToken: OsToken,
    validatorsRegistry: Contract

  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVault']

  beforeEach('deploy fixture', async () => {
    ;[dao, sender, receiver, admin] = await (ethers as any).getSigners()
    ;({
      createEthVault: createVault,
      keeper,
      validatorsRegistry,
      osToken,
      osTokenVaultController,
      vaultsRegistry,
    } = await loadFixture(ethVaultFixture))
    vault = await createVault(admin, vaultParams)

    // collateralize vault
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
    await vault.connect(sender).deposit(sender.address, ZERO_ADDRESS, { value: assets })
  })

  it('cannot mint osTokens from not collateralized vault', async () => {
    const notCollatVault = await createVault(admin, vaultParams, false)
    await expect(
      notCollatVault.connect(sender).mintOsToken(receiver.address, osTokenShares, ZERO_ADDRESS)
    ).to.be.revertedWithCustomError(vault, 'NotCollateralized')
  })

  it('cannot mint osTokens from not harvested vault', async () => {
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
    await expect(
      vault.connect(sender).mintOsToken(receiver.address, osTokenShares, ZERO_ADDRESS)
    ).to.be.revertedWithCustomError(vault, 'NotHarvested')
  })

  it('cannot mint osTokens to zero address', async () => {
    await expect(
      vault.connect(sender).mintOsToken(ZERO_ADDRESS, osTokenShares, ZERO_ADDRESS)
    ).to.be.revertedWithCustomError(vault, 'ZeroAddress')
  })

  it('cannot mint zero osToken shares', async () => {
    await expect(
      vault.connect(sender).mintOsToken(receiver.address, 0, ZERO_ADDRESS)
    ).to.be.revertedWithCustomError(vault, 'InvalidShares')
  })

  it('cannot mint osTokens from unregistered vault', async () => {
    const unknownVault = await createUnknownVaultMock(
      osTokenVaultController,
      await vault.implementation()
    )
    await expect(
      unknownVault.connect(sender).mintOsToken(receiver.address, osTokenShares)
    ).to.be.revertedWithCustomError(vault, 'AccessDenied')
  })

  it('cannot mint osTokens from vault with unsupported implementation', async () => {
    const unknownVault = await createUnknownVaultMock(osTokenVaultController, ZERO_ADDRESS)
    await vaultsRegistry.connect(dao).addVault(await unknownVault.getAddress())
    await expect(
      unknownVault.connect(sender).mintOsToken(receiver.address, osTokenShares)
    ).to.be.revertedWithCustomError(vault, 'AccessDenied')
  })

  it('cannot mint osTokens when it exceeds capacity', async () => {
    const osTokenAssets = await vault.convertToAssets(osTokenShares)
    await osTokenVaultController.connect(dao).setCapacity(osTokenAssets - 1n)
    await expect(
      vault.connect(sender).mintOsToken(receiver.address, osTokenShares, ZERO_ADDRESS)
    ).to.be.revertedWithCustomError(vault, 'CapacityExceeded')
  })

  it('cannot mint osTokens when LTV is violated', async () => {
    const shares = await vault.convertToAssets(assets)
    await expect(
      vault.connect(sender).mintOsToken(receiver.address, shares, ZERO_ADDRESS)
    ).to.be.revertedWithCustomError(vault, 'LowLtv')
  })

  it('cannot enter exit queue when LTV is violated', async () => {
    await vault.connect(sender).mintOsToken(receiver.address, osTokenShares, ZERO_ADDRESS)
    await expect(
      vault.connect(sender).enterExitQueue(assets, receiver.address)
    ).to.be.revertedWithCustomError(vault, 'LowLtv')
  })

  it('updates position accumulated fee', async () => {
    const treasury = await osTokenVaultController.treasury()
    let totalShares = osTokenShares
    let totalAssets = await vault.convertToAssets(osTokenShares)
    let cumulativeFeePerShare = ethers.parseEther('1')
    let treasuryShares = 0n
    let positionShares = osTokenShares
    let receiverShares = osTokenShares

    expect(await osTokenVaultController.cumulativeFeePerShare()).to.eq(cumulativeFeePerShare)
    expect(await vault.osTokenPositions(sender.address)).to.eq(0)

    const verify = async () => {
      expect(await osTokenVaultController.totalShares()).to.eq(totalShares)
      expect(await osTokenVaultController.totalAssets()).to.eq(totalAssets)
      expect(await osTokenVaultController.cumulativeFeePerShare()).to.eq(cumulativeFeePerShare)
      expect(await osToken.balanceOf(treasury)).to.eq(treasuryShares)
      expect(await osToken.balanceOf(sender.address)).to.eq(0)
      expect(await vault.osTokenPositions(sender.address)).to.eq(positionShares)
      expect(await osToken.balanceOf(receiver.address)).to.eq(receiverShares)
    }

    let receipt = await vault
      .connect(sender)
      .mintOsToken(receiver.address, osTokenShares, ZERO_ADDRESS)
    await verify()

    await snapshotGasCost(receipt)
    await increaseTime(ONE_DAY)

    expect(await osTokenVaultController.cumulativeFeePerShare()).to.be.above(cumulativeFeePerShare)
    expect(await osTokenVaultController.totalAssets()).to.be.above(totalAssets)
    expect(await osTokenVaultController.convertToAssets(receiverShares)).to.be.above(osTokenShares)
    expect(await vault.osTokenPositions(sender.address)).to.be.above(positionShares)

    receipt = await vault.connect(sender).mintOsToken(receiver.address, 100, ZERO_ADDRESS)
    receiverShares = receiverShares + 100n
    expect(await osToken.balanceOf(treasury)).to.be.above(0)
    expect(await osTokenVaultController.cumulativeFeePerShare()).to.be.above(cumulativeFeePerShare)

    cumulativeFeePerShare = await osTokenVaultController.cumulativeFeePerShare()
    treasuryShares = await osToken.balanceOf(treasury)
    positionShares = treasuryShares + receiverShares
    totalShares = positionShares
    totalAssets = await osTokenVaultController.convertToAssets(positionShares)
    await verify()

    await snapshotGasCost(receipt)
  })

  it('mints osTokens to the receiver', async () => {
    const receipt = await vault
      .connect(sender)
      .mintOsToken(receiver.address, osTokenShares, ZERO_ADDRESS)
    const osTokenAssets = await vault.convertToAssets(osTokenShares)

    expect(await osTokenVaultController.convertToShares(osTokenAssets)).to.eq(osTokenShares)
    expect(await osToken.balanceOf(receiver.address)).to.eq(osTokenShares)
    expect(await vault.osTokenPositions(sender.address)).to.eq(osTokenShares)
    await expect(receipt)
      .to.emit(vault, 'OsTokenMinted')
      .withArgs(sender.address, receiver.address, osTokenAssets, osTokenShares, ZERO_ADDRESS)
    await expect(receipt)
      .to.emit(osToken, 'Transfer')
      .withArgs(ZERO_ADDRESS, receiver.address, osTokenShares)
    await expect(receipt)
      .to.emit(osTokenVaultController, 'Mint')
      .withArgs(await vault.getAddress(), receiver.address, osTokenAssets, osTokenShares)

    await snapshotGasCost(receipt)
  })
})
