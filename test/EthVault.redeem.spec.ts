import { ethers } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  EthVault,
  IKeeperRewards,
  Keeper,
  OsToken,
  OsTokenConfig,
  OsTokenVaultController,
} from '../typechain-types'
import { ThenArg } from '../helpers/types'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import {
  MAX_UINT16,
  ONE_DAY,
  OSTOKEN_LIQ_BONUS,
  OSTOKEN_LIQ_THRESHOLD,
  OSTOKEN_LTV,
  ZERO_ADDRESS,
} from './shared/constants'
import {
  collateralizeEthVault,
  getRewardsRootProof,
  setAvgRewardPerSecond,
  updateRewards,
} from './shared/rewards'
import { increaseTime, setBalance } from './shared/utils'
import snapshotGasCost from './shared/snapshotGasCost'

describe('EthVault - redeem osToken', () => {
  const shares = ethers.parseEther('32')
  const osTokenShares = ethers.parseEther('28.8')
  const penalty = ethers.parseEther('-0.53')
  const unlockedMevReward = ethers.parseEther('0')
  const redeemedShares = ethers.parseEther('4.76')
  const vaultParams = {
    capacity: ethers.parseEther('1000'),
    feePercent: 1000,
    metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u',
  }
  let owner: Wallet, admin: Wallet, dao: Wallet, redeemer: Wallet, receiver: Wallet
  let vault: EthVault,
    keeper: Keeper,
    osTokenVaultController: OsTokenVaultController,
    osToken: OsToken,
    osTokenConfig: OsTokenConfig,
    validatorsRegistry: Contract

  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVault']

  beforeEach('deploy fixture', async () => {
    ;[dao, owner, redeemer, admin, receiver] = await (ethers as any).getSigners()
    ;({
      createEthVault: createVault,
      keeper,
      validatorsRegistry,
      osTokenVaultController,
      osToken,
      osTokenConfig,
    } = await loadFixture(ethVaultFixture))
    vault = await createVault(admin, vaultParams)
    await osTokenVaultController.connect(dao).setFeePercent(0)

    // collateralize vault
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
    await vault.connect(owner).deposit(owner.address, ZERO_ADDRESS, { value: shares })

    await setAvgRewardPerSecond(dao, vault, keeper, 0)
    await vault.connect(owner).mintOsToken(owner.address, osTokenShares, ZERO_ADDRESS)

    // penalty received
    const tree = await updateRewards(
      keeper,
      [{ vault: await vault.getAddress(), reward: penalty, unlockedMevReward }],
      0
    )
    const harvestParams: IKeeperRewards.HarvestParamsStruct = {
      rewardsRoot: tree.root,
      reward: penalty,
      unlockedMevReward: unlockedMevReward,
      proof: getRewardsRootProof(tree, {
        vault: await vault.getAddress(),
        unlockedMevReward: unlockedMevReward,
        reward: penalty,
      }),
    }
    await vault.connect(dao).updateState(harvestParams)
    await osToken.connect(owner).transfer(redeemer.address, osTokenShares)
  })

  it('cannot redeem osTokens to zero receiver', async () => {
    await expect(
      vault.connect(redeemer).redeemOsToken(redeemedShares, owner.address, ZERO_ADDRESS)
    ).to.be.revertedWithCustomError(vault, 'ZeroAddress')
  })

  it('cannot redeem osTokens from not harvested vault', async () => {
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
      vault.connect(redeemer).redeemOsToken(redeemedShares, owner.address, receiver.address)
    ).to.be.revertedWithCustomError(vault, 'NotHarvested')
  })

  it('cannot redeem osTokens for position with zero minted shares', async () => {
    await expect(
      vault.connect(redeemer).redeemOsToken(redeemedShares, dao.address, receiver.address)
    ).to.be.revertedWithCustomError(vault, 'InvalidPosition')
  })

  it('cannot redeem osTokens when withdrawable assets exceed received assets', async () => {
    await setBalance(await vault.getAddress(), 0n)
    await expect(
      vault.connect(redeemer).redeemOsToken(redeemedShares, owner.address, receiver.address)
    ).to.be.revertedWithCustomError(vault, 'InvalidReceivedAssets')
  })

  it('cannot redeem osTokens when redeeming more than minted', async () => {
    await expect(
      vault.connect(redeemer).redeemOsToken(osTokenShares + 1n, owner.address, receiver.address)
    ).to.be.revertedWithCustomError(osToken, 'ERC20InsufficientBalance')
  })

  it('cannot redeem osTokens when LTV is below redeemFromLtvPercent', async () => {
    await osToken.connect(redeemer).transfer(owner.address, redeemedShares)
    await vault.connect(owner).burnOsToken(redeemedShares)
    await expect(
      vault.connect(redeemer).redeemOsToken(redeemedShares, owner.address, receiver.address)
    ).to.be.revertedWithCustomError(vault, 'InvalidLtv')

    // check with redeems disabled
    await osTokenConfig.connect(dao).updateConfig({
      redeemFromLtvPercent: MAX_UINT16,
      redeemToLtvPercent: MAX_UINT16,
      liqThresholdPercent: OSTOKEN_LIQ_THRESHOLD,
      liqBonusPercent: OSTOKEN_LIQ_BONUS,
      ltvPercent: OSTOKEN_LTV,
    })
    await expect(
      vault.connect(redeemer).redeemOsToken(redeemedShares, owner.address, receiver.address)
    ).to.be.revertedWithCustomError(vault, 'InvalidLtv')
  })

  it('cannot redeem osTokens when LTV is below redeemToLtvPercent', async () => {
    await expect(
      vault
        .connect(redeemer)
        .redeemOsToken(redeemedShares + ethers.parseEther('0.01'), owner.address, receiver.address)
    ).to.be.revertedWithCustomError(vault, 'RedemptionExceeded')
  })

  it('cannot redeem zero osToken shares', async () => {
    await expect(
      vault.connect(redeemer).redeemOsToken(0, owner.address, receiver.address)
    ).to.be.revertedWithCustomError(vault, 'InvalidShares')
  })

  it('cannot redeem without osTokens', async () => {
    await osToken.connect(redeemer).transfer(dao.address, osTokenShares)
    await expect(
      vault.connect(redeemer).redeemOsToken(osTokenShares, owner.address, receiver.address)
    ).to.be.revertedWithCustomError(osToken, 'ERC20InsufficientBalance')
  })

  it('calculates redeem correctly', async () => {
    expect(await osToken.balanceOf(redeemer.address)).to.eq(osTokenShares)
    expect(await vault.osTokenPositions(owner.address)).to.be.eq(osTokenShares)
    expect(await vault.getShares(owner.address)).to.be.eq(shares)

    const balanceBefore = await ethers.provider.getBalance(receiver.address)
    const redeemedAssets = await osTokenVaultController.convertToAssets(redeemedShares)
    const burnedShares = await vault.convertToShares(redeemedAssets)

    const receipt = await vault
      .connect(redeemer)
      .redeemOsToken(redeemedShares, owner.address, receiver.address)

    expect(await osToken.balanceOf(redeemer.address)).to.eq(osTokenShares - redeemedShares)
    expect(await vault.osTokenPositions(owner.address)).to.be.eq(osTokenShares - redeemedShares)
    expect(await vault.getShares(owner.address)).to.be.eq(shares - burnedShares)
    expect(await ethers.provider.getBalance(receiver.address)).to.eq(balanceBefore + redeemedAssets)

    await expect(receipt)
      .to.emit(vault, 'OsTokenRedeemed')
      .withArgs(
        redeemer.address,
        owner.address,
        receiver.address,
        redeemedShares,
        burnedShares,
        redeemedAssets
      )
    await expect(receipt)
      .to.emit(osToken, 'Transfer')
      .withArgs(redeemer.address, ZERO_ADDRESS, redeemedShares)
    await expect(receipt)
      .to.emit(osTokenVaultController, 'Burn')
      .withArgs(await vault.getAddress(), redeemer.address, redeemedShares, redeemedAssets)

    await snapshotGasCost(receipt)
  })

  it('can redeem', async () => {
    const penalty = ethers.parseEther('-0.530001')
    const tree = await updateRewards(keeper, [
      { vault: await vault.getAddress(), reward: penalty, unlockedMevReward },
    ])
    const harvestParams: IKeeperRewards.HarvestParamsStruct = {
      rewardsRoot: tree.root,
      reward: penalty,
      unlockedMevReward: unlockedMevReward,
      proof: getRewardsRootProof(tree, {
        vault: await vault.getAddress(),
        unlockedMevReward: unlockedMevReward,
        reward: penalty,
      }),
    }
    await vault.connect(dao).updateState(harvestParams)

    await increaseTime(ONE_DAY)

    const receipt = await vault
      .connect(redeemer)
      .redeemOsToken(redeemedShares, owner.address, receiver.address)

    await expect(receipt).to.emit(vault, 'OsTokenRedeemed')
    await expect(receipt).to.emit(osToken, 'Transfer')
    await expect(receipt).to.emit(osTokenVaultController, 'Burn')

    await snapshotGasCost(receipt)
  })
})
