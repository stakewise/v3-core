import { ethers } from 'hardhat'
import { Contract, Signer, Wallet } from 'ethers'
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
  OSTOKEN_LIQ_BONUS,
  OSTOKEN_LIQ_THRESHOLD,
  OSTOKEN_LTV,
  OSTOKEN_REDEEM_FROM_LTV,
  OSTOKEN_REDEEM_TO_LTV,
  ZERO_ADDRESS,
} from './shared/constants'
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

describe('EthVault - redeem osToken', () => {
  const assets = ethers.parseEther('32')
  const osTokenAssets = ethers.parseEther('28.8')
  let shares: bigint
  let osTokenShares: bigint
  const unlockedMevReward = ethers.parseEther('0')
  const redeemedAssets = ethers.parseEther('4.76')
  let redeemedShares: bigint
  const vaultParams = {
    capacity: ethers.parseEther('1000'),
    feePercent: 1000,
    metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u',
  }
  let owner: Wallet, admin: Signer, dao: Wallet, redeemer: Wallet, receiver: Wallet
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
    admin = await ethers.getImpersonatedSigner(await vault.admin())
    await osTokenVaultController.connect(dao).setFeePercent(0)

    // collateralize vault
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
    const tx = await vault.connect(owner).deposit(owner.address, ZERO_ADDRESS, { value: assets })
    shares = await extractDepositShares(tx)

    await setAvgRewardPerSecond(dao, vault, keeper, 0)
    await osTokenConfig.connect(dao).updateConfig({
      redeemFromLtvPercent: OSTOKEN_REDEEM_FROM_LTV,
      redeemToLtvPercent: OSTOKEN_REDEEM_TO_LTV,
      liqThresholdPercent: OSTOKEN_LIQ_THRESHOLD,
      liqBonusPercent: OSTOKEN_LIQ_BONUS,
      ltvPercent: OSTOKEN_LTV,
    })
    osTokenShares = await osTokenVaultController.convertToShares(osTokenAssets)
    redeemedShares = await osTokenVaultController.convertToShares(redeemedAssets)
    await vault.connect(owner).mintOsToken(owner.address, osTokenShares, ZERO_ADDRESS)

    // penalty received
    // slash 1% of assets
    const penalty = -((await vault.totalAssets()) * 2n) / 100n
    const vaultReward = getHarvestParams(await vault.getAddress(), penalty, unlockedMevReward)
    const tree = await updateRewards(keeper, [vaultReward], 0)
    const harvestParams: IKeeperRewards.HarvestParamsStruct = {
      rewardsRoot: tree.root,
      reward: vaultReward.reward,
      unlockedMevReward: vaultReward.unlockedMevReward,
      proof: getRewardsRootProof(tree, vaultReward),
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
      vault.connect(redeemer).redeemOsToken(osTokenShares, owner.address, receiver.address)
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
    let burnedShares = await vault.convertToShares(redeemedAssets)
    let receiverAssets = redeemedAssets

    const receipt = await vault
      .connect(redeemer)
      .redeemOsToken(redeemedShares, owner.address, receiver.address)

    if (MAINNET_FORK.enabled) {
      burnedShares -= 1n // rounding error
      receiverAssets -= 1n // rounding error
    }

    expect(await osToken.balanceOf(redeemer.address)).to.eq(osTokenShares - redeemedShares)
    expect(await vault.osTokenPositions(owner.address)).to.be.eq(osTokenShares - redeemedShares)
    expect(await vault.getShares(owner.address)).to.be.eq(shares - burnedShares)
    expect(await ethers.provider.getBalance(receiver.address)).to.eq(balanceBefore + receiverAssets)

    await expect(receipt)
      .to.emit(vault, 'OsTokenRedeemed')
      .withArgs(
        redeemer.address,
        owner.address,
        receiver.address,
        redeemedShares,
        burnedShares,
        receiverAssets
      )
    await expect(receipt)
      .to.emit(osToken, 'Transfer')
      .withArgs(redeemer.address, ZERO_ADDRESS, redeemedShares)
    await expect(receipt)
      .to.emit(osTokenVaultController, 'Burn')
      .withArgs(await vault.getAddress(), redeemer.address, receiverAssets, redeemedShares)

    await snapshotGasCost(receipt)
  })

  it('can redeem', async () => {
    const receipt = await vault
      .connect(redeemer)
      .redeemOsToken(redeemedShares, owner.address, receiver.address)

    await expect(receipt).to.emit(vault, 'OsTokenRedeemed')
    await expect(receipt).to.emit(osToken, 'Transfer')
    await expect(receipt).to.emit(osTokenVaultController, 'Burn')

    await snapshotGasCost(receipt)
  })
})
