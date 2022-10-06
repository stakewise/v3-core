import { ethers, waffle } from 'hardhat'
import { Wallet } from 'ethers'
import { EthVault, ExitQueue } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import snapshotGasCost from './shared/snapshotGasCost'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { MAX_INT256, PANIC_CODES, ZERO_ADDRESS } from './shared/constants'
import { setBalance } from './shared/utils'

const createFixtureLoader = waffle.createFixtureLoader

describe('EthVault - harvest', () => {
  const maxTotalAssets = ethers.utils.parseEther('1000')
  const feePercent = 1000
  const vaultName = 'SW ETH Vault'
  const vaultSymbol = 'SW-ETH-1'
  let keeper: Wallet, holder: Wallet, receiver: Wallet, operator: Wallet, other: Wallet
  let vault: EthVault
  const holderAssets = ethers.utils.parseEther('1')
  const holderShares = ethers.utils.parseEther('1')

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createVault']

  before('create fixture loader', async () => {
    ;[keeper, holder, receiver, operator, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([keeper, operator])
  })

  beforeEach('deploy fixture', async () => {
    ;({ createVault } = await loadFixture(ethVaultFixture))
    vault = await createVault(vaultName, vaultSymbol, feePercent, maxTotalAssets)
    await vault.connect(holder).deposit(holder.address, { value: holderAssets })
  })

  it('does not fail with zero assets delta', async () => {
    const assetsDelta = await vault.connect(keeper).callStatic.harvest(0)
    expect(assetsDelta).to.be.eq(0)
    await expect(vault.connect(keeper).harvest(0)).to.emit(vault, 'Harvested')
  })

  it('reverts when overflow', async () => {
    await expect(vault.connect(keeper).harvest(MAX_INT256)).revertedWith(
      "SafeCast: value doesn't fit in 128 bits"
    )
  })

  it('reverts when underflow', async () => {
    await expect(vault.connect(keeper).harvest(ethers.utils.parseEther('-2'))).revertedWith(
      PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW
    )
  })

  it('only keeper can update', async () => {
    await expect(vault.connect(operator).harvest(1)).revertedWith('NotKeeper()')
  })

  it('applies penalty when delta is below zero', async () => {
    const penalty = ethers.utils.parseEther('-0.5')
    const rewardFeesEscrow = ethers.utils.parseEther('0.3')
    const reward = penalty.add(rewardFeesEscrow)
    await setBalance(await vault.feesEscrow(), rewardFeesEscrow)

    const assetsDelta = await vault.connect(keeper).callStatic.harvest(penalty)
    expect(assetsDelta).to.be.eq(reward)

    const totalSupplyBefore = await vault.totalSupply()
    const totalAssetsBefore = await vault.totalAssets()
    const receipt = await vault.connect(keeper).harvest(penalty)

    await expect(receipt).emit(vault, 'Harvested').withArgs(reward)
    expect(await waffle.provider.getBalance(vault.address)).to.be.eq(
      rewardFeesEscrow.add(holderAssets)
    )
    expect(await vault.totalSupply()).to.be.eq(totalSupplyBefore)
    expect(await vault.totalAssets()).to.be.eq(totalAssetsBefore.add(reward))
    await snapshotGasCost(receipt)
  })

  it('allocates fee to operator when delta is above zero', async () => {
    const rewardValidators = ethers.utils.parseEther('0.5')
    const rewardFeesEscrow = ethers.utils.parseEther('0.5')
    const operatorReward = ethers.utils.parseEther('0.1')
    const reward = rewardValidators.add(rewardFeesEscrow)

    const feesEscrow = await vault.feesEscrow()
    await setBalance(feesEscrow, rewardFeesEscrow)

    const assetsDelta = await vault.connect(keeper).callStatic.harvest(rewardValidators)
    expect(assetsDelta).to.be.eq(reward)

    const totalSupplyBefore = await vault.totalSupply()
    const totalAssetsBefore = await vault.totalAssets()
    const receipt = await vault.connect(keeper).harvest(rewardValidators)

    const operatorShares = await vault.balanceOf(operator.address)
    expect(await vault.convertToAssets(operatorShares)).to.be.eq(operatorReward.sub(1)) // rounding error
    expect(await vault.convertToShares(operatorReward)).to.be.eq(operatorShares)
    expect(await waffle.provider.getBalance(feesEscrow)).to.be.eq(0)

    await expect(receipt).emit(vault, 'Harvested').withArgs(reward)
    await expect(receipt)
      .emit(vault, 'Transfer')
      .withArgs(ZERO_ADDRESS, operator.address, operatorShares)
    expect(await waffle.provider.getBalance(vault.address)).to.be.eq(
      rewardFeesEscrow.add(holderAssets)
    )
    expect(await vault.totalSupply()).to.be.eq(totalSupplyBefore.add(operatorShares))
    expect(await vault.totalAssets()).to.be.eq(totalAssetsBefore.add(reward))
    await snapshotGasCost(receipt)
  })

  it('updates exit queue', async () => {
    const exitQueueFactory = await ethers.getContractFactory('ExitQueue')
    const exitQueue = exitQueueFactory.attach(vault.address) as ExitQueue
    await vault.connect(holder).enterExitQueue(holderShares, holder.address, holder.address)

    const totalSupplyBefore = await vault.totalSupply()
    const totalAssetsBefore = await vault.totalAssets()

    const rewardValidators = ethers.utils.parseEther('0.5')
    const rewardFeesEscrow = ethers.utils.parseEther('0.5')
    const reward = rewardValidators.add(rewardFeesEscrow)
    const feesEscrow = await vault.feesEscrow()
    await setBalance(feesEscrow, rewardFeesEscrow)

    const receipt = await vault.connect(keeper).harvest(rewardValidators)

    const operatorShares = await vault.balanceOf(operator.address)
    expect(await waffle.provider.getBalance(feesEscrow)).to.be.eq(0)
    expect(await waffle.provider.getBalance(vault.address)).to.be.eq(
      rewardFeesEscrow.add(holderAssets)
    )
    await expect(receipt).emit(vault, 'Harvested').withArgs(reward)
    await expect(receipt).emit(exitQueue, 'CheckpointCreated')

    let totalSupplyAfter = totalSupplyBefore.add(operatorShares)
    let totalAssetsAfter = totalAssetsBefore.add(reward)

    const unclaimedAssets = holderAssets.add(rewardFeesEscrow)
    const burnedShares = unclaimedAssets.mul(totalSupplyAfter).div(totalAssetsAfter)

    totalSupplyAfter = totalSupplyAfter.sub(burnedShares)
    totalAssetsAfter = totalAssetsAfter.sub(unclaimedAssets)

    expect(await vault.totalSupply()).to.be.eq(totalSupplyAfter)
    expect(await vault.totalAssets()).to.be.eq(totalAssetsAfter)
    expect(await vault.unclaimedAssets()).to.be.eq(unclaimedAssets)
    await snapshotGasCost(receipt)
  })
})
