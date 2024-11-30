import { ethers } from 'hardhat'
import { Contract, ContractTransactionReceipt, Signer, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  EthVault,
  Keeper,
  OsTokenVaultController,
  OsToken,
  DepositDataRegistry,
} from '../typechain-types'
import { ThenArg } from '../helpers/types'
import snapshotGasCost from './shared/snapshotGasCost'
import { createUnknownVaultMock, ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { ONE_DAY, ZERO_ADDRESS } from './shared/constants'
import { collateralizeEthVault, setAvgRewardPerSecond } from './shared/rewards'
import { increaseTime } from './shared/utils'

describe('EthVault - burn', () => {
  const assets = ethers.parseEther('2')
  const osTokenAssets = ethers.parseEther('1')
  let osTokenShares: bigint
  const vaultParams = {
    capacity: ethers.parseEther('1000'),
    feePercent: 1000,
    metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u',
  }
  let sender: Wallet, admin: Signer, owner: Wallet
  let vault: EthVault,
    keeper: Keeper,
    osTokenVaultController: OsTokenVaultController,
    osToken: OsToken,
    validatorsRegistry: Contract,
    depositDataRegistry: DepositDataRegistry

  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVault']

  beforeEach('deploy fixture', async () => {
    ;[sender, owner, admin] = (await (ethers as any).getSigners()).slice(1, 4)
    ;({
      createEthVault: createVault,
      keeper,
      validatorsRegistry,
      osToken,
      osTokenVaultController,
      depositDataRegistry,
    } = await loadFixture(ethVaultFixture))
    vault = await createVault(admin, vaultParams)
    admin = await ethers.getImpersonatedSigner(await vault.admin())

    // collateralize vault
    await collateralizeEthVault(vault, keeper, depositDataRegistry, admin, validatorsRegistry)
    await vault.connect(sender).deposit(sender.address, ZERO_ADDRESS, { value: assets })
    osTokenShares = await osTokenVaultController.convertToShares(osTokenAssets)
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
    await setAvgRewardPerSecond(owner, vault, keeper, 1005987242)
    const treasury = await osTokenVaultController.treasury()
    const currTotalShares = await osTokenVaultController.totalShares()
    const currTotalAssets = await osTokenVaultController.totalAssets()
    const currCumulativeFeePerShare = await osTokenVaultController.cumulativeFeePerShare()
    const currTreasuryShares = await osToken.balanceOf(treasury)
    const currPositionShares = await vault.osTokenPositions(sender.address)

    await increaseTime(ONE_DAY)

    const newTotalShares = await osTokenVaultController.totalShares()
    const newTotalAssets = await osTokenVaultController.totalAssets()
    const newCumulativeFeePerShare = await osTokenVaultController.cumulativeFeePerShare()
    const newTreasuryShares = await osToken.balanceOf(treasury)
    const newPositionShares = await vault.osTokenPositions(sender.address)
    expect(newTotalShares).to.be.eq(currTotalShares)
    expect(newTotalAssets).to.be.above(currTotalAssets)
    expect(newCumulativeFeePerShare).to.be.above(currCumulativeFeePerShare)
    expect(newTreasuryShares).to.be.eq(currTreasuryShares)
    expect(newPositionShares).to.be.above(currPositionShares)

    const receipt = await vault.connect(sender).burnOsToken(osTokenShares)
    expect(await vault.osTokenPositions(sender.address)).to.be.above(
      newPositionShares - currPositionShares
    )
    await snapshotGasCost(receipt)
  })

  it('burns osTokens', async () => {
    await setAvgRewardPerSecond(owner, vault, keeper, 1005987242)
    const tx = await vault.connect(sender).burnOsToken(osTokenShares)
    const receipt = (await tx.wait()) as ContractTransactionReceipt
    // eslint-disable-next-line @typescript-eslint/ban-ts-comment
    // @ts-ignore
    const osTokenAssets = receipt.logs?.[receipt.logs.length - 1]?.args?.assets

    expect(await osToken.balanceOf(sender.address)).to.eq(0)
    expect(await vault.osTokenPositions(sender.address)).to.be.above(0)
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
