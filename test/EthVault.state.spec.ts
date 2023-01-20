import { ethers, waffle } from 'hardhat'
import { BigNumber, Contract, Wallet } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import { Keeper, EthVault, ExitQueue, Oracles } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import snapshotGasCost from './shared/snapshotGasCost'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { PANIC_CODES, ZERO_ADDRESS, ZERO_BYTES32 } from './shared/constants'
import { setBalance } from './shared/utils'
import { collateralizeEthVault, getRewardsRootProof, updateRewardsRoot } from './shared/rewards'

const createFixtureLoader = waffle.createFixtureLoader

describe('EthVault - state', () => {
  const holderAssets = parseEther('1')
  const holderShares = parseEther('1')
  const capacity = parseEther('1000')
  const feePercent = 1000
  const name = 'SW ETH Vault'
  const symbol = 'SW-ETH-1'
  const validatorsRoot = '0x059a8487a1ce461e9670c4646ef85164ae8791613866d28c972fb351dc45c606'
  const validatorsIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7r'
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'

  let holder: Wallet, admin: Wallet, dao: Wallet
  let vault: EthVault, keeper: Keeper, oracles: Oracles, validatorsRegistry: Contract

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createVault']
  let getSignatures: ThenArg<ReturnType<typeof ethVaultFixture>>['getSignatures']

  before('create fixture loader', async () => {
    ;[holder, admin, dao] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([dao])
  })

  beforeEach('deploy fixture', async () => {
    ;({ createVault, keeper, oracles, validatorsRegistry, getSignatures } = await loadFixture(
      ethVaultFixture
    ))
    vault = await createVault(admin, {
      capacity,
      validatorsRoot,
      feePercent,
      name,
      symbol,
      validatorsIpfsHash,
      metadataIpfsHash,
    })
    await vault.connect(holder).deposit(holder.address, { value: holderAssets })
  })

  it('does not fail with zero assets delta', async () => {
    const tree = await updateRewardsRoot(keeper, oracles, getSignatures, [
      { vault: vault.address, reward: 0 },
    ])
    const proof = getRewardsRootProof(tree, { vault: vault.address, reward: 0 })
    await expect(vault.updateState({ rewardsRoot: tree.root, reward: 0, proof })).to.not.emit(
      vault,
      'StateUpdated'
    )
  })

  it('reverts when overflow', async () => {
    const reward = BigNumber.from(2).pow(160).sub(1).div(2)
    const tree = await updateRewardsRoot(keeper, oracles, getSignatures, [
      { vault: vault.address, reward },
    ])
    await expect(
      vault.updateState({
        rewardsRoot: tree.root,
        reward,
        proof: getRewardsRootProof(tree, {
          vault: vault.address,
          reward,
        }),
      })
    ).revertedWith("SafeCast: value doesn't fit in 128 bits")
  })

  it('reverts when underflow', async () => {
    const reward = parseEther('-2')
    const tree = await updateRewardsRoot(keeper, oracles, getSignatures, [
      { vault: vault.address, reward },
    ])
    await expect(
      vault.updateState({
        rewardsRoot: tree.root,
        reward,
        proof: getRewardsRootProof(tree, {
          vault: vault.address,
          reward,
        }),
      })
    ).revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
  })

  it('only vault can harvest', async () => {
    await expect(keeper.harvest({ rewardsRoot: ZERO_BYTES32, reward: 0, proof: [] })).revertedWith(
      'AccessDenied()'
    )
  })

  it('applies penalty when delta is below zero', async () => {
    const penalty = parseEther('-0.5')
    const rewardMevEscrow = parseEther('0.3')
    const reward = penalty.add(rewardMevEscrow)
    await setBalance(await vault.mevEscrow(), rewardMevEscrow)
    const tree = await updateRewardsRoot(keeper, oracles, getSignatures, [
      { vault: vault.address, reward: penalty },
    ])
    const proof = getRewardsRootProof(tree, { vault: vault.address, reward: penalty })

    const totalSupplyBefore = await vault.totalSupply()
    const totalAssetsBefore = await vault.totalAssets()
    const receipt = await vault.updateState({ rewardsRoot: tree.root, reward: penalty, proof })

    await expect(receipt).emit(vault, 'StateUpdated').withArgs(reward)
    expect(await waffle.provider.getBalance(vault.address)).to.be.eq(
      rewardMevEscrow.add(holderAssets)
    )
    expect(await vault.totalSupply()).to.be.eq(totalSupplyBefore)
    expect(await vault.totalAssets()).to.be.eq(totalAssetsBefore.add(reward))
    await snapshotGasCost(receipt)
  })

  it('allocates fee to recipient when delta is above zero', async () => {
    const rewardValidators = parseEther('0.5')
    const rewardMevEscrow = parseEther('0.5')
    const operatorReward = parseEther('0.1')
    const reward = rewardValidators.add(rewardMevEscrow)

    const mevEscrow = await vault.mevEscrow()
    await setBalance(mevEscrow, rewardMevEscrow)
    const tree = await updateRewardsRoot(keeper, oracles, getSignatures, [
      {
        vault: vault.address,
        reward: rewardValidators,
      },
    ])
    const proof = getRewardsRootProof(tree, { vault: vault.address, reward: rewardValidators })

    const totalSupplyBefore = await vault.totalSupply()
    const totalAssetsBefore = await vault.totalAssets()
    const receipt = await vault.updateState({
      rewardsRoot: tree.root,
      reward: rewardValidators,
      proof,
    })

    const operatorShares = await vault.balanceOf(admin.address)
    expect(await vault.convertToAssets(operatorShares)).to.be.eq(operatorReward.sub(1)) // rounding error
    expect(await vault.convertToShares(operatorReward)).to.be.eq(operatorShares)
    expect(await waffle.provider.getBalance(mevEscrow)).to.be.eq(0)

    await expect(receipt).emit(vault, 'StateUpdated').withArgs(reward)
    await expect(receipt)
      .emit(vault, 'Transfer')
      .withArgs(ZERO_ADDRESS, admin.address, operatorShares)
    expect(await waffle.provider.getBalance(vault.address)).to.be.eq(
      rewardMevEscrow.add(holderAssets)
    )
    expect(await vault.totalSupply()).to.be.eq(totalSupplyBefore.add(operatorShares))
    expect(await vault.totalAssets()).to.be.eq(totalAssetsBefore.add(reward))
    await snapshotGasCost(receipt)
  })

  it('updates exit queue', async () => {
    const exitQueueFactory = await ethers.getContractFactory('ExitQueue')
    const exitQueue = exitQueueFactory.attach(vault.address) as ExitQueue
    await collateralizeEthVault(vault, oracles, keeper, validatorsRegistry, admin, getSignatures)
    await vault.connect(holder).enterExitQueue(holderShares, holder.address, holder.address)

    const totalSupplyBefore = await vault.totalSupply()
    const totalAssetsBefore = await vault.totalAssets()

    const rewardValidators = parseEther('0.5')
    const rewardMevEscrow = parseEther('0.5')
    const reward = rewardValidators.add(rewardMevEscrow)
    const mevEscrow = await vault.mevEscrow()
    await setBalance(mevEscrow, rewardMevEscrow)
    const tree = await updateRewardsRoot(keeper, oracles, getSignatures, [
      {
        vault: vault.address,
        reward: rewardValidators,
      },
    ])
    const proof = getRewardsRootProof(tree, { vault: vault.address, reward: rewardValidators })

    const receipt = await vault.updateState({
      rewardsRoot: tree.root,
      reward: rewardValidators,
      proof,
    })
    const operatorShares = await vault.balanceOf(admin.address)
    expect(await waffle.provider.getBalance(mevEscrow)).to.be.eq(0)
    expect(await waffle.provider.getBalance(vault.address)).to.be.eq(
      rewardMevEscrow.add(holderAssets)
    )
    await expect(receipt).emit(vault, 'StateUpdated').withArgs(reward)
    await expect(receipt).emit(exitQueue, 'CheckpointCreated')

    let totalSupplyAfter = totalSupplyBefore.add(operatorShares)
    let totalAssetsAfter = totalAssetsBefore.add(reward)

    const unclaimedAssets = holderAssets.add(rewardMevEscrow)
    const burnedShares = unclaimedAssets.mul(totalSupplyAfter).div(totalAssetsAfter)

    totalSupplyAfter = totalSupplyAfter.sub(burnedShares)
    totalAssetsAfter = totalAssetsAfter.sub(unclaimedAssets)

    expect(await vault.totalSupply()).to.be.eq(totalSupplyAfter)
    expect(await vault.totalAssets()).to.be.eq(totalAssetsAfter)
    expect(await vault.unclaimedAssets()).to.be.eq(unclaimedAssets)
    await snapshotGasCost(receipt)
  })
})
