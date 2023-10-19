import { ethers } from 'hardhat'
import { Contract, ContractTransactionReceipt, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { EthVault, Keeper, OsTokenVaultController, OsToken } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import snapshotGasCost from './shared/snapshotGasCost'
import { createUnknownVaultMock, ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { ONE_DAY, ZERO_ADDRESS } from './shared/constants'
import { collateralizeEthVault } from './shared/rewards'
import { increaseTime } from './shared/utils'

describe('EthVault - burn', () => {
  const assets = ethers.parseEther('2')
  const osTokenAssets = ethers.parseEther('1')
  const osTokenShares = ethers.parseEther('1')
  const vaultParams = {
    capacity: ethers.parseEther('1000'),
    feePercent: 1000,
    metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u',
  }
  let sender: Wallet, admin: Wallet, owner: Wallet
  let vault: EthVault,
    keeper: Keeper,
    osTokenVaultController: OsTokenVaultController,
    osToken: OsToken,
    validatorsRegistry: Contract

  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVault']

  beforeEach('deploy fixture', async () => {
    ;[sender, owner, admin] = (await (ethers as any).getSigners()).slice(1, 4)
    ;({
      createEthVault: createVault,
      keeper,
      validatorsRegistry,
      osToken,
      osTokenVaultController,
    } = await loadFixture(ethVaultFixture))
    vault = await createVault(admin, vaultParams)

    // collateralize vault
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
    await vault.connect(sender).deposit(sender.address, ZERO_ADDRESS, { value: assets })
    await vault.connect(sender).mintOsToken(sender.address, osTokenShares, ZERO_ADDRESS)
  })

  it('cannot burn zero osTokens', async () => {
    await expect(vault.connect(sender).burnOsToken(0)).to.be.revertedWithCustomError(
      vault,
      'InvalidShares'
    )
  })

  it('cannot burn osTokens when nothing is minted', async () => {
    await osToken.connect(sender).transfer(owner.address, osTokenShares)
    await expect(vault.connect(owner).burnOsToken(osTokenShares)).to.be.revertedWithCustomError(
      vault,
      'InvalidPosition'
    )
  })

  it('cannot burn osTokens from unregistered vault', async () => {
    const unknownVault = await createUnknownVaultMock(
      osTokenVaultController,
      await vault.implementation()
    )
    await expect(
      unknownVault.connect(sender).burnOsToken(osTokenShares)
    ).to.be.revertedWithCustomError(vault, 'AccessDenied')
  })

  it('updates position accumulated fee', async () => {
    const treasury = await osTokenVaultController.treasury()
    let totalShares = osTokenShares
    let totalAssets = osTokenAssets
    let cumulativeFeePerShare = ethers.parseEther('1')
    let treasuryShares = 0n
    let positionShares = osTokenShares

    expect(await osTokenVaultController.cumulativeFeePerShare()).to.eq(cumulativeFeePerShare)
    expect(await vault.osTokenPositions(sender.address)).to.eq(positionShares)

    await increaseTime(ONE_DAY)

    expect(await osTokenVaultController.cumulativeFeePerShare()).to.be.above(cumulativeFeePerShare)
    expect(await osTokenVaultController.totalAssets()).to.be.above(totalAssets)
    expect(await vault.osTokenPositions(sender.address)).to.be.above(positionShares)

    const receipt = await vault.connect(sender).burnOsToken(osTokenShares)
    expect(await osToken.balanceOf(treasury)).to.be.above(0)
    expect(await osTokenVaultController.cumulativeFeePerShare()).to.be.above(cumulativeFeePerShare)
    await snapshotGasCost(receipt)

    cumulativeFeePerShare = await osTokenVaultController.cumulativeFeePerShare()
    treasuryShares = await osToken.balanceOf(treasury)
    positionShares = treasuryShares
    totalShares = treasuryShares
    totalAssets = await osTokenVaultController.convertToAssets(treasuryShares)
    expect(await osTokenVaultController.totalShares()).to.eq(totalShares)
    expect(await osTokenVaultController.totalAssets()).to.eq(totalAssets)
    expect(await osTokenVaultController.cumulativeFeePerShare()).to.eq(cumulativeFeePerShare)
    expect(await osToken.balanceOf(treasury)).to.eq(treasuryShares)
    expect(await osToken.balanceOf(sender.address)).to.eq(0)
    expect(await vault.osTokenPositions(sender.address)).to.eq(positionShares)
  })

  it('burns osTokens', async () => {
    const tx = await vault.connect(sender).burnOsToken(osTokenShares)
    const receipt = (await tx.wait()) as ContractTransactionReceipt
    // eslint-disable-next-line @typescript-eslint/ban-ts-comment
    // @ts-ignore
    const osTokenAssets = receipt.logs?.[receipt.logs.length - 1]?.args?.assets

    expect(await osToken.balanceOf(sender.address)).to.eq(0)
    expect(await vault.osTokenPositions(sender.address)).to.eq(
      await osToken.balanceOf(await osTokenVaultController.treasury())
    )
    await expect(tx)
      .to.emit(vault, 'OsTokenBurned')
      .withArgs(sender.address, osTokenAssets, osTokenShares)
    await expect(tx)
      .to.emit(osToken, 'Transfer')
      .withArgs(sender.address, ZERO_ADDRESS, osTokenShares)
    await expect(tx)
      .to.emit(osTokenVaultController, 'Burn')
      .withArgs(await vault.getAddress(), sender.address, osTokenAssets, osTokenShares)

    await snapshotGasCost(tx)
  })
})
