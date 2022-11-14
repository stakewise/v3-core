import { ethers, waffle } from 'hardhat'
import { BigNumber, Wallet } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import { EthKeeper, EthVault, ExitQueue, Signers } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import snapshotGasCost from './shared/snapshotGasCost'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { PANIC_CODES, ZERO_ADDRESS } from './shared/constants'
import { setBalance } from './shared/utils'
import { getRewardsRootProof, updateRewardsRoot } from './shared/rewards'

const createFixtureLoader = waffle.createFixtureLoader

describe('EthVault - harvest', () => {
  const holderAssets = parseEther('1')
  const holderShares = parseEther('1')
  const maxTotalAssets = parseEther('1000')
  const feePercent = 1000
  const vaultName = 'SW ETH Vault'
  const vaultSymbol = 'SW-ETH-1'
  const validatorsRoot = '0x059a8487a1ce461e9670c4646ef85164ae8791613866d28c972fb351dc45c606'
  const validatorsIpfsHash = '/ipfs/QmfPnyNojfyqoi9yqS3jMp16GGiTQee4bdCXJC64KqvTgc'

  let holder: Wallet, operator: Wallet, dao: Wallet
  let vault: EthVault, keeper: EthKeeper, signers: Signers

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createVault']
  let getSignatures: ThenArg<ReturnType<typeof ethVaultFixture>>['getSignatures']

  before('create fixture loader', async () => {
    ;[holder, operator, dao] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([dao])
  })

  beforeEach('deploy fixture', async () => {
    ;({ createVault, keeper, signers, getSignatures } = await loadFixture(ethVaultFixture))
    vault = await createVault(
      operator,
      maxTotalAssets,
      validatorsRoot,
      feePercent,
      vaultName,
      vaultSymbol,
      validatorsIpfsHash
    )
    await vault.connect(holder).deposit(holder.address, { value: holderAssets })
  })

  it('does not fail with zero assets delta', async () => {
    const tree = await updateRewardsRoot(keeper, signers, getSignatures, [
      { vault: vault.address, reward: 0 },
    ])
    const proof = getRewardsRootProof(tree, { vault: vault.address, reward: 0 })
    const assetsDelta = await keeper.callStatic.harvest(vault.address, 0, proof)
    expect(assetsDelta).to.be.eq(0)
    await expect(keeper.harvest(vault.address, 0, proof)).to.emit(vault, 'StateUpdated').withArgs(0)
  })

  it('reverts when overflow', async () => {
    const reward = BigNumber.from(2).pow(160).sub(1).div(2)
    const tree = await updateRewardsRoot(keeper, signers, getSignatures, [
      { vault: vault.address, reward },
    ])
    await expect(
      keeper.harvest(
        vault.address,
        reward,
        getRewardsRootProof(tree, { vault: vault.address, reward })
      )
    ).revertedWith("SafeCast: value doesn't fit in 128 bits")
  })

  it('reverts when underflow', async () => {
    const reward = parseEther('-2')
    const tree = await updateRewardsRoot(keeper, signers, getSignatures, [
      { vault: vault.address, reward },
    ])
    await expect(
      keeper.harvest(
        vault.address,
        reward,
        getRewardsRootProof(tree, { vault: vault.address, reward })
      )
    ).revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
  })

  it('only keeper can update', async () => {
    await expect(vault.connect(operator).updateState(1)).revertedWith('AccessDenied()')
  })

  it('applies penalty when delta is below zero', async () => {
    const penalty = parseEther('-0.5')
    const rewardFeesEscrow = parseEther('0.3')
    const reward = penalty.add(rewardFeesEscrow)
    await setBalance(await vault.feesEscrow(), rewardFeesEscrow)
    const tree = await updateRewardsRoot(keeper, signers, getSignatures, [
      { vault: vault.address, reward: penalty },
    ])
    const proof = getRewardsRootProof(tree, { vault: vault.address, reward: penalty })

    const assetsDelta = await keeper.callStatic.harvest(vault.address, penalty, proof)
    expect(assetsDelta).to.be.eq(reward)

    const totalSupplyBefore = await vault.totalSupply()
    const totalAssetsBefore = await vault.totalAssets()
    const receipt = await keeper.harvest(vault.address, penalty, proof)

    await expect(receipt).emit(vault, 'StateUpdated').withArgs(reward)
    expect(await waffle.provider.getBalance(vault.address)).to.be.eq(
      rewardFeesEscrow.add(holderAssets)
    )
    expect(await vault.totalSupply()).to.be.eq(totalSupplyBefore)
    expect(await vault.totalAssets()).to.be.eq(totalAssetsBefore.add(reward))
    await snapshotGasCost(receipt)
  })

  it('allocates fee to operator when delta is above zero', async () => {
    const rewardValidators = parseEther('0.5')
    const rewardFeesEscrow = parseEther('0.5')
    const operatorReward = parseEther('0.1')
    const reward = rewardValidators.add(rewardFeesEscrow)

    const feesEscrow = await vault.feesEscrow()
    await setBalance(feesEscrow, rewardFeesEscrow)
    const tree = await updateRewardsRoot(keeper, signers, getSignatures, [
      { vault: vault.address, reward: rewardValidators },
    ])
    const proof = getRewardsRootProof(tree, { vault: vault.address, reward: rewardValidators })

    const assetsDelta = await keeper.callStatic.harvest(vault.address, rewardValidators, proof)
    expect(assetsDelta).to.be.eq(reward)

    const totalSupplyBefore = await vault.totalSupply()
    const totalAssetsBefore = await vault.totalAssets()
    const receipt = await keeper.harvest(vault.address, rewardValidators, proof)

    const operatorShares = await vault.balanceOf(operator.address)
    expect(await vault.convertToAssets(operatorShares)).to.be.eq(operatorReward.sub(1)) // rounding error
    expect(await vault.convertToShares(operatorReward)).to.be.eq(operatorShares)
    expect(await waffle.provider.getBalance(feesEscrow)).to.be.eq(0)

    await expect(receipt).emit(vault, 'StateUpdated').withArgs(reward)
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

    const rewardValidators = parseEther('0.5')
    const rewardFeesEscrow = parseEther('0.5')
    const reward = rewardValidators.add(rewardFeesEscrow)
    const feesEscrow = await vault.feesEscrow()
    await setBalance(feesEscrow, rewardFeesEscrow)
    const tree = await updateRewardsRoot(keeper, signers, getSignatures, [
      { vault: vault.address, reward: rewardValidators },
    ])
    const proof = getRewardsRootProof(tree, { vault: vault.address, reward: rewardValidators })

    const receipt = await keeper.harvest(vault.address, rewardValidators, proof)
    const operatorShares = await vault.balanceOf(operator.address)
    expect(await waffle.provider.getBalance(feesEscrow)).to.be.eq(0)
    expect(await waffle.provider.getBalance(vault.address)).to.be.eq(
      rewardFeesEscrow.add(holderAssets)
    )
    await expect(receipt).emit(vault, 'StateUpdated').withArgs(reward)
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
