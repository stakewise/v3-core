import { ethers, waffle } from 'hardhat'
import { BigNumber, Contract, Wallet } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import { EthVault, Keeper, Oracles, OsToken, IKeeperRewards } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { ONE_DAY, PANIC_CODES, ZERO_ADDRESS } from './shared/constants'
import { collateralizeEthVault, getRewardsRootProof, updateRewards } from './shared/rewards'
import { increaseTime, setBalance } from './shared/utils'
import snapshotGasCost from './shared/snapshotGasCost'

const createFixtureLoader = waffle.createFixtureLoader

describe('EthVault - redeem osToken', () => {
  const shares = parseEther('32')
  const osTokenShares = parseEther('28.8')
  const penalty = parseEther('-0.53')
  const unlockedMevReward = parseEther('0')
  const redeemedShares = parseEther('4.76')
  const vaultParams = {
    capacity: parseEther('1000'),
    feePercent: 1000,
    name: 'SW ETH Vault',
    symbol: 'SW-ETH-1',
    metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u',
  }
  let owner: Wallet, admin: Wallet, dao: Wallet, redeemer: Wallet, receiver: Wallet
  let vault: EthVault,
    keeper: Keeper,
    oracles: Oracles,
    osToken: OsToken,
    validatorsRegistry: Contract

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createVault']
  let getSignatures: ThenArg<ReturnType<typeof ethVaultFixture>>['getSignatures']

  before('create fixture loader', async () => {
    ;[owner, redeemer, dao, admin, receiver] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([dao])
  })

  beforeEach('deploy fixture', async () => {
    ;({ createVault, getSignatures, keeper, oracles, validatorsRegistry, osToken } =
      await loadFixture(ethVaultFixture))
    vault = await createVault(admin, vaultParams)
    await osToken.connect(dao).setVaultImplementation(await vault.implementation(), true)
    await osToken.connect(dao).setFeePercent(0)

    // collateralize vault
    await collateralizeEthVault(vault, oracles, keeper, validatorsRegistry, admin, getSignatures)
    await vault.connect(owner).deposit(owner.address, ZERO_ADDRESS, { value: shares })

    // penalty received
    const tree = await updateRewards(
      keeper,
      oracles,
      getSignatures,
      [{ vault: vault.address, reward: penalty, unlockedMevReward }],
      0
    )
    await vault.connect(owner).mintOsToken(owner.address, osTokenShares, ZERO_ADDRESS)
    const harvestParams: IKeeperRewards.HarvestParamsStruct = {
      rewardsRoot: tree.root,
      reward: penalty,
      unlockedMevReward: unlockedMevReward,
      proof: getRewardsRootProof(tree, {
        vault: vault.address,
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
    ).to.be.revertedWith('InvalidRecipient')
  })

  it('cannot redeem osTokens from not harvested vault', async () => {
    await updateRewards(keeper, oracles, getSignatures, [
      { vault: vault.address, reward: parseEther('1'), unlockedMevReward: parseEther('0') },
    ])
    await updateRewards(keeper, oracles, getSignatures, [
      { vault: vault.address, reward: parseEther('1.2'), unlockedMevReward: parseEther('0') },
    ])
    await expect(
      vault.connect(redeemer).redeemOsToken(redeemedShares, owner.address, receiver.address)
    ).to.be.revertedWith('NotHarvested')
  })

  it('cannot redeem osTokens for position with zero minted shares', async () => {
    await expect(
      vault.connect(redeemer).redeemOsToken(redeemedShares, dao.address, receiver.address)
    ).to.be.revertedWith('InvalidPosition')
  })

  it('cannot redeem osTokens when withdrawable assets exceed received assets', async () => {
    await setBalance(vault.address, BigNumber.from(0))
    await expect(
      vault.connect(redeemer).redeemOsToken(redeemedShares, owner.address, receiver.address)
    ).to.be.revertedWith('InvalidReceivedAssets')
  })

  it('cannot redeem osTokens when redeeming more than minted', async () => {
    await expect(
      vault.connect(redeemer).redeemOsToken(osTokenShares.add(1), owner.address, receiver.address)
    ).to.be.revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
  })

  it('cannot redeem osTokens when LTV is below redeemFromLtvPercent', async () => {
    await osToken.connect(redeemer).transfer(owner.address, redeemedShares)
    await vault.connect(owner).burnOsToken(redeemedShares)
    await expect(
      vault.connect(redeemer).redeemOsToken(redeemedShares, owner.address, receiver.address)
    ).to.be.revertedWith('InvalidLtv')
  })

  it('cannot redeem osTokens when LTV is below redeemToLtvPercent', async () => {
    await expect(
      vault
        .connect(redeemer)
        .redeemOsToken(redeemedShares.add(parseEther('0.01')), owner.address, receiver.address)
    ).to.be.revertedWith('RedemptionExceeded')
  })

  it('cannot redeem zero osToken shares', async () => {
    await expect(
      vault.connect(redeemer).redeemOsToken(0, owner.address, receiver.address)
    ).to.be.revertedWith('InvalidShares')
  })

  it('cannot redeem without osTokens', async () => {
    await osToken.connect(redeemer).transfer(dao.address, osTokenShares)
    await expect(
      vault.connect(redeemer).redeemOsToken(osTokenShares, owner.address, receiver.address)
    ).to.be.revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
  })

  it('calculates redeem correctly', async () => {
    expect(await osToken.balanceOf(redeemer.address)).to.eq(osTokenShares)
    expect(await vault.osTokenPositions(owner.address)).to.be.eq(osTokenShares)
    expect(await vault.balanceOf(owner.address)).to.be.eq(shares)

    const balanceBefore = await waffle.provider.getBalance(receiver.address)
    const redeemedAssets = await osToken.convertToAssets(redeemedShares)
    const burnedShares = await vault.convertToShares(redeemedAssets)

    const receipt = await vault
      .connect(redeemer)
      .redeemOsToken(redeemedShares, owner.address, receiver.address)

    expect(await osToken.balanceOf(redeemer.address)).to.eq(osTokenShares.sub(redeemedShares))
    expect(await vault.osTokenPositions(owner.address)).to.be.eq(osTokenShares.sub(redeemedShares))
    expect(await vault.balanceOf(owner.address)).to.be.eq(shares.sub(burnedShares))
    expect(await waffle.provider.getBalance(receiver.address)).to.eq(
      balanceBefore.add(redeemedAssets)
    )

    await expect(receipt)
      .to.emit(vault, 'OsTokenRedeemed')
      .withArgs(redeemer.address, owner.address, receiver.address, redeemedShares, redeemedAssets)
    await expect(receipt)
      .to.emit(osToken, 'Transfer')
      .withArgs(redeemer.address, ZERO_ADDRESS, redeemedShares)
    await expect(receipt)
      .to.emit(vault, 'Transfer')
      .withArgs(owner.address, ZERO_ADDRESS, burnedShares)
    await expect(receipt)
      .to.emit(osToken, 'Burn')
      .withArgs(vault.address, redeemer.address, redeemedShares, redeemedAssets)

    await snapshotGasCost(receipt)
  })

  it('can redeem', async () => {
    const penalty = parseEther('-0.530001')
    const tree = await updateRewards(keeper, oracles, getSignatures, [
      { vault: vault.address, reward: penalty, unlockedMevReward },
    ])
    const harvestParams: IKeeperRewards.HarvestParamsStruct = {
      rewardsRoot: tree.root,
      reward: penalty,
      unlockedMevReward: unlockedMevReward,
      proof: getRewardsRootProof(tree, {
        vault: vault.address,
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
    await expect(receipt).to.emit(vault, 'Transfer')
    await expect(receipt).to.emit(osToken, 'Burn')

    await snapshotGasCost(receipt)
  })
})
