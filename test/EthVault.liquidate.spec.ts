import { ethers } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { EthVault, IKeeperRewards, Keeper, OsToken } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { ONE_DAY, OSTOKEN_LIQ_BONUS, PANIC_CODES, ZERO_ADDRESS } from './shared/constants'
import {
  collateralizeEthVault,
  getRewardsRootProof,
  setAvgRewardPerSecond,
  updateRewards,
} from './shared/rewards'
import { increaseTime, setBalance } from './shared/utils'
import snapshotGasCost from './shared/snapshotGasCost'

describe('EthVault - liquidate', () => {
  const shares = ethers.parseEther('32')
  const osTokenShares = ethers.parseEther('28.8')
  const penalty = ethers.parseEther('-2.6')
  const unlockedMevReward = ethers.parseEther('0')
  const vaultParams = {
    capacity: ethers.parseEther('1000'),
    feePercent: 1000,
    metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u',
  }
  let owner: Wallet, admin: Wallet, dao: Wallet, liquidator: Wallet, receiver: Wallet
  let vault: EthVault, keeper: Keeper, osToken: OsToken, validatorsRegistry: Contract

  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVault']

  beforeEach('deploy fixture', async () => {
    ;[dao, owner, liquidator, admin, receiver] = await (ethers as any).getSigners()
    ;({
      createEthVault: createVault,
      keeper,
      validatorsRegistry,
      osToken,
    } = await loadFixture(ethVaultFixture))
    vault = await createVault(admin, vaultParams)
    await osToken.connect(dao).setFeePercent(0)

    // collateralize vault
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
    await vault.connect(owner).deposit(owner.address, ZERO_ADDRESS, { value: shares })

    // set avg reward per second to 0
    await setAvgRewardPerSecond(dao, vault, keeper, 0)

    // mint osTokens
    await vault.connect(owner).mintOsToken(owner.address, osTokenShares, ZERO_ADDRESS)

    // slashing received
    const tree = await updateRewards(
      keeper,
      [{ vault: await vault.getAddress(), reward: penalty, unlockedMevReward }],
      0
    )
    const harvestParams = {
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
    await osToken.connect(owner).transfer(liquidator.address, osTokenShares)
  })

  it('cannot liquidate osTokens to zero receiver', async () => {
    await expect(
      vault.connect(liquidator).liquidateOsToken(osTokenShares, owner.address, ZERO_ADDRESS)
    ).to.be.revertedWithCustomError(vault, 'ZeroAddress')
  })

  it('cannot liquidate osTokens from not harvested vault', async () => {
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
      vault.connect(liquidator).liquidateOsToken(osTokenShares, owner.address, receiver.address)
    ).to.be.revertedWithCustomError(vault, 'NotHarvested')
  })

  it('cannot liquidate osTokens for position with zero minted shares', async () => {
    await expect(
      vault.connect(liquidator).liquidateOsToken(osTokenShares, dao.address, receiver.address)
    ).to.be.revertedWithCustomError(vault, 'InvalidPosition')
  })

  it('cannot liquidate osTokens when received assets exceed deposited assets', async () => {
    await expect(
      vault.connect(liquidator).liquidateOsToken(shares + 1n, owner.address, receiver.address)
    ).to.be.revertedWithCustomError(vault, 'InvalidReceivedAssets')
  })

  it('cannot liquidate osTokens when withdrawable assets exceed received assets', async () => {
    await setBalance(await vault.getAddress(), 0n)
    await expect(
      vault.connect(liquidator).liquidateOsToken(osTokenShares, owner.address, receiver.address)
    ).to.be.revertedWithCustomError(vault, 'InvalidReceivedAssets')
  })

  it('cannot liquidate osTokens when liquidating more than minted', async () => {
    await expect(
      vault
        .connect(liquidator)
        .liquidateOsToken(osTokenShares + 1n, owner.address, receiver.address)
    ).to.be.revertedWithPanic(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
  })

  it('cannot liquidate osTokens when health factor is above 1', async () => {
    await osToken.connect(liquidator).transfer(owner.address, osTokenShares)
    const liqShares = osTokenShares / 2n
    await vault.connect(owner).burnOsToken(liqShares)
    await expect(
      vault.connect(liquidator).liquidateOsToken(liqShares, owner.address, receiver.address)
    ).to.be.revertedWithCustomError(vault, 'InvalidHealthFactor')
  })

  it('cannot liquidate zero osToken shares', async () => {
    await expect(
      vault.connect(liquidator).liquidateOsToken(0, owner.address, receiver.address)
    ).to.be.revertedWithCustomError(vault, 'InvalidShares')
  })

  it('cannot liquidate without osTokens', async () => {
    await osToken.connect(liquidator).transfer(dao.address, osTokenShares)
    await expect(
      vault.connect(liquidator).liquidateOsToken(osTokenShares, owner.address, receiver.address)
    ).to.be.revertedWithPanic(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
  })

  it('calculates liquidation correctly', async () => {
    expect(await osToken.balanceOf(liquidator.address)).to.eq(osTokenShares)
    expect(await vault.osTokenPositions(owner.address)).to.be.eq(osTokenShares)
    expect(await vault.getShares(owner.address)).to.be.eq(shares)

    const balanceBefore = await ethers.provider.getBalance(receiver.address)
    const osTokenAssets = (osTokenShares * BigInt(OSTOKEN_LIQ_BONUS)) / 10000n
    const burnedShares = await vault.convertToShares(osTokenAssets)

    const receipt = await vault
      .connect(liquidator)
      .liquidateOsToken(osTokenShares, owner.address, receiver.address)

    expect(await osToken.balanceOf(liquidator.address)).to.eq(0)
    expect(await vault.osTokenPositions(owner.address)).to.be.eq(0)
    expect(await vault.getShares(owner.address)).to.be.eq(shares - burnedShares)
    expect(await ethers.provider.getBalance(receiver.address)).to.eq(balanceBefore + osTokenAssets)

    await expect(receipt)
      .to.emit(vault, 'OsTokenLiquidated')
      .withArgs(liquidator.address, owner.address, receiver.address, osTokenShares, osTokenAssets)
    await expect(receipt)
      .to.emit(osToken, 'Transfer')
      .withArgs(liquidator.address, ZERO_ADDRESS, osTokenShares)
    await expect(receipt)
      .to.emit(osToken, 'Burn')
      .withArgs(await vault.getAddress(), liquidator.address, osTokenShares, osTokenShares)

    await snapshotGasCost(receipt)
  })

  it('can liquidate', async () => {
    const penalty = ethers.parseEther('-2.6001')
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
      .connect(liquidator)
      .liquidateOsToken(osTokenShares, owner.address, receiver.address)

    await expect(receipt).to.emit(vault, 'OsTokenLiquidated')
    await expect(receipt).to.emit(osToken, 'Transfer')
    await expect(receipt).to.emit(osToken, 'Burn')

    await snapshotGasCost(receipt)
  })
})
