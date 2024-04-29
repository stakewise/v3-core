import { ethers } from 'hardhat'
import { Contract, Signer, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  EthVault,
  Keeper,
  OsToken,
  OsTokenConfig,
  OsTokenVaultController,
  DepositDataRegistry,
} from '../typechain-types'
import { ThenArg } from '../helpers/types'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { ZERO_ADDRESS } from './shared/constants'
import {
  collateralizeEthVault,
  getHarvestParams,
  getRewardsRootProof,
  setAvgRewardPerSecond,
  updateRewards,
} from './shared/rewards'
import { extractDepositShares, setBalance } from './shared/utils'
import snapshotGasCost from './shared/snapshotGasCost'
import { MAINNET_FORK } from '../helpers/constants'

describe('EthVault - liquidate', () => {
  const assets = ethers.parseEther('32')
  let shares: bigint
  const osTokenAssets = ethers.parseEther('28.8')
  let osTokenShares: bigint
  const unlockedMevReward = ethers.parseEther('0')
  const vaultParams = {
    capacity: ethers.parseEther('1000'),
    feePercent: 1000,
    metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u',
  }
  let owner: Wallet, admin: Signer, dao: Wallet, liquidator: Wallet, receiver: Wallet
  let vault: EthVault,
    keeper: Keeper,
    osTokenVaultController: OsTokenVaultController,
    osToken: OsToken,
    osTokenConfig: OsTokenConfig,
    validatorsRegistry: Contract,
    depositDataRegistry: DepositDataRegistry

  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVault']

  beforeEach('deploy fixture', async () => {
    ;[dao, owner, liquidator, admin, receiver] = await (ethers as any).getSigners()
    ;({
      createEthVault: createVault,
      keeper,
      validatorsRegistry,
      osTokenVaultController,
      osToken,
      osTokenConfig,
      depositDataRegistry,
    } = await loadFixture(ethVaultFixture))
    vault = await createVault(admin, vaultParams)
    admin = await ethers.getImpersonatedSigner(await vault.admin())
    await osTokenVaultController.connect(dao).setFeePercent(0)

    // collateralize vault
    await collateralizeEthVault(vault, keeper, depositDataRegistry, admin, validatorsRegistry)
    const tx = await vault.connect(owner).deposit(owner.address, ZERO_ADDRESS, { value: assets })
    shares = await extractDepositShares(tx)

    // set avg reward per second to 0
    await setAvgRewardPerSecond(dao, vault, keeper, 0)

    // mint osTokens
    osTokenShares = await osTokenVaultController.convertToShares(osTokenAssets)
    await vault.connect(owner).mintOsToken(owner.address, osTokenShares, ZERO_ADDRESS)

    // slash 5% of assets
    const penalty = -((await vault.totalAssets()) * 5n) / 100n

    // slashing received
    const vaultReward = getHarvestParams(await vault.getAddress(), penalty, unlockedMevReward)
    const tree = await updateRewards(keeper, [vaultReward], 0)
    const harvestParams = {
      rewardsRoot: tree.root,
      reward: vaultReward.reward,
      unlockedMevReward: vaultReward.unlockedMevReward,
      proof: getRewardsRootProof(tree, vaultReward),
    }
    await vault.connect(dao).updateState(harvestParams)
    await osToken.connect(owner).transfer(liquidator.address, osTokenShares)
    await osTokenConfig.connect(dao).setLiquidator(liquidator.address)
  })

  it('cannot liquidate osTokens from not liquidator', async () => {
    await osTokenConfig.connect(dao).setLiquidator(dao.address)
    await expect(
      vault.connect(liquidator).liquidateOsToken(osTokenShares, owner.address, ZERO_ADDRESS)
    ).to.be.revertedWithCustomError(vault, 'AccessDenied')
  })

  it('cannot liquidate osTokens to zero receiver', async () => {
    await expect(
      vault.connect(liquidator).liquidateOsToken(osTokenShares, owner.address, ZERO_ADDRESS)
    ).to.be.revertedWithCustomError(vault, 'ZeroAddress')
  })

  it('cannot liquidate osTokens from not harvested vault', async () => {
    await updateRewards(keeper, [
      getHarvestParams(await vault.getAddress(), ethers.parseEther('1'), 0n),
    ])
    await updateRewards(keeper, [
      getHarvestParams(await vault.getAddress(), ethers.parseEther('1.2'), 0n),
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
    ).to.be.revertedWithCustomError(osToken, 'ERC20InsufficientBalance')
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
    ).to.be.revertedWithCustomError(osToken, 'ERC20InsufficientBalance')
  })

  it('calculates liquidation correctly', async () => {
    expect(await osToken.balanceOf(liquidator.address)).to.eq(osTokenShares)
    expect(await vault.osTokenPositions(owner.address)).to.be.eq(osTokenShares)
    expect(await vault.getShares(owner.address)).to.be.eq(shares)

    const balanceBefore = await ethers.provider.getBalance(receiver.address)
    const liqBonus = await osTokenConfig.liqBonusPercent()
    let liquidatorAssets = (osTokenAssets * BigInt(liqBonus)) / 10000n
    if (MAINNET_FORK.enabled) {
      liquidatorAssets -= 2n // rounding error
    }
    const burnedShares = await vault.convertToShares(liquidatorAssets)

    const receipt = await vault
      .connect(liquidator)
      .liquidateOsToken(osTokenShares, owner.address, receiver.address)

    expect(await osToken.balanceOf(liquidator.address)).to.eq(0)
    expect(await vault.osTokenPositions(owner.address)).to.be.eq(0)
    expect(await vault.getShares(owner.address)).to.be.eq(shares - burnedShares)
    expect(await ethers.provider.getBalance(receiver.address)).to.eq(
      balanceBefore + liquidatorAssets
    )

    await expect(receipt)
      .to.emit(vault, 'OsTokenLiquidated')
      .withArgs(
        liquidator.address,
        owner.address,
        receiver.address,
        osTokenShares,
        burnedShares,
        liquidatorAssets
      )
    await expect(receipt)
      .to.emit(osToken, 'Transfer')
      .withArgs(liquidator.address, ZERO_ADDRESS, osTokenShares)

    let burnedAssets = osTokenAssets
    if (MAINNET_FORK.enabled) {
      burnedAssets -= 1n // rounding error
    }

    await expect(receipt)
      .to.emit(osTokenVaultController, 'Burn')
      .withArgs(await vault.getAddress(), liquidator.address, burnedAssets, osTokenShares) // rounding error

    await snapshotGasCost(receipt)
  })

  it('can liquidate', async () => {
    const receipt = await vault
      .connect(liquidator)
      .liquidateOsToken(osTokenShares, owner.address, receiver.address)

    await expect(receipt).to.emit(vault, 'OsTokenLiquidated')
    await expect(receipt).to.emit(osToken, 'Transfer')
    await expect(receipt).to.emit(osTokenVaultController, 'Burn')

    await snapshotGasCost(receipt)
  })
})
