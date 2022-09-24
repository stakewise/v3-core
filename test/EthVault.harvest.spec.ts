import { ethers, waffle } from 'hardhat'
import { Wallet } from 'ethers'
import { EthVault } from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { vaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { MAX_INT256, PANIC_CODES, ZERO_ADDRESS } from './shared/constants'
import { setBalance } from './shared/utils'

const createFixtureLoader = waffle.createFixtureLoader

type ThenArg<T> = T extends PromiseLike<infer U> ? U : T

describe('EthVault - harvest', () => {
  const maxTotalAssets = ethers.utils.parseEther('1000')
  const feePercent = 1000
  let keeper: Wallet, holder: Wallet, receiver: Wallet, operator: Wallet, other: Wallet
  let vault: EthVault
  const holderAssets = ethers.utils.parseEther('1')

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createEthVault: ThenArg<ReturnType<typeof vaultFixture>>['createEthVault']

  before('create fixture loader', async () => {
    ;[keeper, holder, receiver, operator, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([keeper, holder, receiver, other])
  })

  beforeEach('deploy fixture', async () => {
    ;({ createEthVault } = await loadFixture(vaultFixture))
    vault = await createEthVault(keeper.address, operator.address, maxTotalAssets, feePercent)
    await vault.connect(holder).deposit(holder.address, { value: holderAssets })
  })

  it('returns zero with no validator and fees escrow assets', async () => {
    const assetsDelta = await vault.connect(keeper).callStatic.harvest(0)
    expect(assetsDelta).to.be.eq(0)
    await expect(vault.connect(keeper).harvest(0)).to.not.emit(vault, 'Harvested')
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
    const assetsDelta = await vault.connect(keeper).callStatic.harvest(penalty)
    expect(assetsDelta).to.be.eq(penalty)

    const totalSupplyBefore = await vault.totalSupply()
    const totalAssetsBefore = await vault.totalAssets()
    const receipt = await vault.connect(keeper).harvest(penalty)

    expect(receipt).emit(vault, 'Harvested').withArgs(penalty)
    expect(await vault.totalSupply()).to.be.eq(totalSupplyBefore)
    expect(await vault.totalAssets()).to.be.eq(totalAssetsBefore.add(penalty))
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

    expect(receipt).emit(vault, 'Harvested').withArgs(reward)
    expect(receipt).emit(vault, 'Transfer').withArgs(ZERO_ADDRESS, operator.address, operatorShares)
    expect(await vault.totalSupply()).to.be.eq(totalSupplyBefore.add(operatorShares))
    expect(await vault.totalAssets()).to.be.eq(totalAssetsBefore.add(reward))
    await snapshotGasCost(receipt)
  })
})
