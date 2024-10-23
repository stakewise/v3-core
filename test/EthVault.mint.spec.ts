import { ethers } from 'hardhat'
import { Contract, Signer, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  EthVault,
  Keeper,
  OsToken,
  VaultsRegistry,
  OsTokenVaultController,
  DepositDataRegistry,
  OsTokenConfig,
  IKeeperRewards,
} from '../typechain-types'
import { ThenArg } from '../helpers/types'
import snapshotGasCost from './shared/snapshotGasCost'
import { createUnknownVaultMock, ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { MAX_UINT256, ONE_DAY, ZERO_ADDRESS } from './shared/constants'
import {
  collateralizeEthVault,
  getHarvestParams,
  getRewardsRootProof,
  setAvgRewardPerSecond,
  updateRewards,
} from './shared/rewards'
import { extractDepositShares, increaseTime } from './shared/utils'
import { MAINNET_FORK } from '../helpers/constants'

describe('EthVault - mint', () => {
  const assets = ethers.parseEther('2')
  let shares: bigint
  let osTokenShares: bigint
  const vaultParams = {
    capacity: ethers.parseEther('1000'),
    feePercent: 1000,
    metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u',
  }
  let dao: Wallet, sender: Wallet, receiver: Wallet, admin: Signer, other: Wallet
  let vault: EthVault,
    keeper: Keeper,
    vaultsRegistry: VaultsRegistry,
    osTokenVaultController: OsTokenVaultController,
    osToken: OsToken,
    validatorsRegistry: Contract,
    depositDataRegistry: DepositDataRegistry,
    osTokenConfig: OsTokenConfig

  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVault']

  beforeEach('deploy fixture', async () => {
    ;[dao, sender, receiver, admin, other] = await (ethers as any).getSigners()
    ;({
      createEthVault: createVault,
      keeper,
      validatorsRegistry,
      osToken,
      osTokenVaultController,
      vaultsRegistry,
      depositDataRegistry,
      osTokenConfig,
    } = await loadFixture(ethVaultFixture))
    vault = await createVault(admin, vaultParams)
    admin = await ethers.getImpersonatedSigner(await vault.admin())

    // collateralize vault
    await collateralizeEthVault(vault, keeper, depositDataRegistry, admin, validatorsRegistry)
    const tx = await vault.connect(sender).deposit(sender.address, ZERO_ADDRESS, { value: assets })
    shares = await extractDepositShares(tx)
    osTokenShares = await osTokenVaultController.convertToShares(assets / 2n)
  })

  it('cannot mint osTokens from not collateralized vault', async () => {
    const notCollatVault = await createVault(admin, vaultParams, false, true)
    await expect(
      notCollatVault.connect(sender).mintOsToken(receiver.address, osTokenShares, ZERO_ADDRESS)
    ).to.be.revertedWithCustomError(vault, 'NotCollateralized')
  })

  it('cannot mint osTokens from not harvested vault', async () => {
    const vaultAddr = await vault.getAddress()
    await updateRewards(keeper, [
      getHarvestParams(vaultAddr, ethers.parseEther('1'), ethers.parseEther('0')),
    ])
    await updateRewards(keeper, [
      getHarvestParams(vaultAddr, ethers.parseEther('1.2'), ethers.parseEther('0')),
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
      vault.connect(sender).enterExitQueue(shares, receiver.address)
    ).to.be.revertedWithCustomError(vault, 'LowLtv')
  })

  it('updates position accumulated fee', async () => {
    await vault.connect(dao).deposit(dao.address, ZERO_ADDRESS, {
      value: await osTokenVaultController.convertToAssets(osTokenShares * 2n),
    })
    await vault.connect(dao).mintOsToken(dao.address, osTokenShares, ZERO_ADDRESS)
    await setAvgRewardPerSecond(dao, vault, keeper, 1005987242)

    const currTotalShares = await osTokenVaultController.totalShares()
    const currTotalAssets = await osTokenVaultController.totalAssets()
    const currCumulativeFeePerShare = await osTokenVaultController.cumulativeFeePerShare()

    expect(await vault.osTokenPositions(sender.address)).to.eq(0n)

    await increaseTime(ONE_DAY)

    await vault.connect(sender).mintOsToken(receiver.address, osTokenShares, ZERO_ADDRESS)
    const newTotalShares = await osTokenVaultController.totalShares()
    const newTotalAssets = await osTokenVaultController.totalAssets()
    expect(newTotalShares).to.be.above(currTotalShares + osTokenShares)
    expect(newTotalAssets).to.be.above(currTotalAssets)
    expect(await osTokenVaultController.cumulativeFeePerShare()).to.be.above(
      currCumulativeFeePerShare
    )
    const currPositionShares = await vault.osTokenPositions(sender.address)
    await increaseTime(ONE_DAY)
    expect(await vault.osTokenPositions(sender.address)).to.be.above(currPositionShares)

    const newShares = 10n
    const newAssets = await osTokenVaultController.convertToAssets(newShares)
    const receipt = await vault
      .connect(sender)
      .mintOsToken(receiver.address, newShares, ZERO_ADDRESS)
    expect(await osTokenVaultController.totalShares()).to.be.above(newTotalShares + 10n)
    expect(await osTokenVaultController.totalAssets()).to.be.above(newTotalAssets + newAssets)
    expect(await osTokenVaultController.cumulativeFeePerShare()).to.be.above(
      currCumulativeFeePerShare
    )
    expect(await vault.osTokenPositions(sender.address)).to.be.above(currPositionShares + newShares)

    await snapshotGasCost(receipt)
  })

  it('mints osTokens to the receiver', async () => {
    const receipt = await vault
      .connect(sender)
      .mintOsToken(receiver.address, osTokenShares, ZERO_ADDRESS)
    const osTokenAssets = await osTokenVaultController.convertToAssets(osTokenShares)

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

  it('can deposit and mint osToken in one transaction', async () => {
    await setAvgRewardPerSecond(dao, vault, keeper, 0)
    expect(await vault.osTokenPositions(other.address)).to.eq(0n)
    expect(await vault.getShares(other.address)).to.eq(0n)

    const config = await osTokenConfig.getConfig(await vault.getAddress())
    let osTokenAssets = (assets * config.ltvPercent) / ethers.parseEther('1')
    let osTokenShares = await osTokenVaultController.convertToShares(osTokenAssets)

    // mint max shares
    let receipt = await vault
      .connect(other)
      .depositAndMintOsToken(receiver.address, osTokenShares, ZERO_ADDRESS, { value: assets })

    if (MAINNET_FORK.enabled) {
      osTokenAssets -= 1n // rounding error
    }

    expect(await osToken.balanceOf(receiver.address)).to.eq(osTokenShares)
    expect(await vault.osTokenPositions(other.address)).to.eq(osTokenShares)
    expect(await vault.getShares(other.address)).to.eq(shares)
    await expect(receipt)
      .to.emit(vault, 'Deposited')
      .withArgs(other.address, other.address, assets, shares, ZERO_ADDRESS)
    await expect(receipt)
      .to.emit(vault, 'OsTokenMinted')
      .withArgs(other.address, receiver.address, osTokenAssets, osTokenShares, ZERO_ADDRESS)
    await snapshotGasCost(receipt)

    // mint half shares
    osTokenAssets = assets / 2n
    osTokenShares = await osTokenVaultController.convertToShares(osTokenAssets)
    receipt = await vault
      .connect(sender)
      .depositAndMintOsToken(other.address, osTokenShares, ZERO_ADDRESS, { value: assets })

    expect(await osToken.balanceOf(other.address)).to.eq(osTokenShares)
    expect(await vault.osTokenPositions(sender.address)).to.eq(osTokenShares)
    expect(await vault.getShares(sender.address)).to.eq(shares * 2n)
    await expect(receipt)
      .to.emit(vault, 'Deposited')
      .withArgs(sender.address, sender.address, assets, shares, ZERO_ADDRESS)
    await expect(receipt)
      .to.emit(vault, 'OsTokenMinted')
      .withArgs(sender.address, other.address, osTokenAssets, osTokenShares, ZERO_ADDRESS)
    await snapshotGasCost(receipt)
  })

  it('can update state, deposit, and mint osToken in one transaction', async () => {
    await setAvgRewardPerSecond(dao, vault, keeper, 0)
    const vaultAddr = await vault.getAddress()

    await updateRewards(
      keeper,
      [getHarvestParams(vaultAddr, ethers.parseEther('1'), ethers.parseEther('0'))],
      0
    )

    const tree = await updateRewards(
      keeper,
      [getHarvestParams(vaultAddr, ethers.parseEther('1.2'), ethers.parseEther('0'))],
      0
    )
    const vaultReward = getHarvestParams(
      vaultAddr,
      ethers.parseEther('1.2'),
      ethers.parseEther('0')
    )
    const harvestParams: IKeeperRewards.HarvestParamsStruct = {
      rewardsRoot: tree.root,
      reward: vaultReward.reward,
      unlockedMevReward: vaultReward.unlockedMevReward,
      proof: getRewardsRootProof(tree, vaultReward),
    }
    const sharesBefore = await vault.convertToShares(assets)

    expect(await vault.osTokenPositions(other.address)).to.eq(0n)
    expect(await vault.getShares(other.address)).to.eq(0n)

    const config = await osTokenConfig.getConfig(await vault.getAddress())
    let osTokenAssets = (assets * config.ltvPercent) / ethers.parseEther('1')
    const osTokenShares = await osTokenVaultController.convertToShares(osTokenAssets)
    osTokenAssets = await osTokenVaultController.convertToAssets(osTokenShares)

    const receipt = await vault
      .connect(other)
      .updateStateAndDepositAndMintOsToken(
        receiver.address,
        MAX_UINT256,
        ZERO_ADDRESS,
        harvestParams,
        {
          value: assets,
        }
      )
    let sharesAfter = await vault.convertToShares(assets)
    sharesAfter += 1n // rounding error

    expect(sharesBefore).to.gt(sharesAfter)
    expect(await osToken.balanceOf(receiver.address)).to.eq(osTokenShares)
    expect(await vault.osTokenPositions(other.address)).to.eq(osTokenShares)
    expect(await vault.getShares(other.address)).to.eq(sharesAfter)
    await expect(receipt)
      .to.emit(vault, 'Deposited')
      .withArgs(other.address, other.address, assets, sharesAfter, ZERO_ADDRESS)
    await expect(receipt)
      .to.emit(vault, 'OsTokenMinted')
      .withArgs(other.address, receiver.address, osTokenAssets, osTokenShares, ZERO_ADDRESS)
    await snapshotGasCost(receipt)
  })
})
