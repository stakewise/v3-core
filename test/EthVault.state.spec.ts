import { ethers, waffle } from 'hardhat'
import { BigNumber, Contract, Wallet } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import { EthVault, Keeper, OwnMevEscrow, SharedMevEscrow } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import snapshotGasCost from './shared/snapshotGasCost'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import {
  MAX_UINT256,
  PANIC_CODES,
  SECURITY_DEPOSIT,
  ZERO_ADDRESS,
  ZERO_BYTES32,
} from './shared/constants'
import { setBalance } from './shared/utils'
import { collateralizeEthVault, getRewardsRootProof, updateRewards } from './shared/rewards'

const createFixtureLoader = waffle.createFixtureLoader

describe('EthVault - state', () => {
  const holderAssets = parseEther('1')
  const holderShares = parseEther('1')
  const capacity = parseEther('1000')
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'

  let holder: Wallet, admin: Wallet, dao: Wallet, other: Wallet
  let vault: EthVault,
    keeper: Keeper,
    sharedMevEscrow: SharedMevEscrow,
    validatorsRegistry: Contract

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVault']
  let createVaultMock: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVaultMock']

  before('create fixture loader', async () => {
    ;[holder, admin, dao, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([dao])
  })

  beforeEach('deploy fixture', async () => {
    ;({
      createEthVault: createVault,
      createEthVaultMock: createVaultMock,
      keeper,
      validatorsRegistry,
      sharedMevEscrow,
    } = await loadFixture(ethVaultFixture))
    vault = await createVault(admin, {
      capacity,
      feePercent,
      metadataIpfsHash,
    })
    await vault.connect(holder).deposit(holder.address, ZERO_ADDRESS, { value: holderAssets })
  })

  it('does not fail with zero assets delta', async () => {
    const tree = await updateRewards(keeper, [
      { vault: vault.address, unlockedMevReward: 0, reward: 0 },
    ])
    const proof = getRewardsRootProof(tree, {
      vault: vault.address,
      unlockedMevReward: 0,
      reward: 0,
    })
    const receipt = await vault.updateState({
      rewardsRoot: tree.root,
      reward: 0,
      unlockedMevReward: 0,
      proof,
    })
    await expect(receipt).to.emit(keeper, 'Harvested').withArgs(vault.address, tree.root, 0, 0)
    await expect(receipt).to.not.emit(sharedMevEscrow, 'Harvested')
  })

  it('reverts when overflow', async () => {
    const reward = BigNumber.from(2).pow(160).sub(1).div(2)
    const unlockedMevReward = BigNumber.from(2).pow(160).sub(1)
    const tree = await updateRewards(keeper, [{ vault: vault.address, reward, unlockedMevReward }])
    await setBalance(sharedMevEscrow.address, unlockedMevReward)
    await expect(
      vault.updateState({
        rewardsRoot: tree.root,
        reward,
        unlockedMevReward,
        proof: getRewardsRootProof(tree, {
          vault: vault.address,
          reward,
          unlockedMevReward,
        }),
      })
    ).revertedWith("SafeCast: value doesn't fit in 128 bits")
  })

  it('reverts when underflow', async () => {
    const reward = parseEther('-2')
    const tree = await updateRewards(keeper, [
      { vault: vault.address, reward, unlockedMevReward: 0 },
    ])
    await expect(
      vault.updateState({
        rewardsRoot: tree.root,
        reward,
        unlockedMevReward: 0,
        proof: getRewardsRootProof(tree, {
          vault: vault.address,
          reward,
          unlockedMevReward: 0,
        }),
      })
    ).revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
  })

  it('is not affected by inflation attack', async () => {
    const vault = await createVaultMock(
      admin,
      {
        capacity: MAX_UINT256,
        feePercent: 0,
        metadataIpfsHash,
      },
      true
    )
    const securityDeposit = BigNumber.from('1000000000')
    await vault.connect(other).deposit(other.address, ZERO_ADDRESS, { value: 1 })
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
    await vault._setTotalAssets(1)
    expect(await vault.totalAssets()).to.eq(1)
    expect(await vault.totalSupply()).to.eq(securityDeposit.add(1))

    // attacker drops a lot of eth as a reward
    const burnedAssets = parseEther('1000')
    await setBalance(await vault.mevEscrow(), burnedAssets)

    // state is updated
    const tree = await updateRewards(keeper, [
      { vault: vault.address, reward: 0, unlockedMevReward: 1 },
    ])
    await vault.updateState({
      rewardsRoot: tree.root,
      reward: 0,
      unlockedMevReward: 1,
      proof: getRewardsRootProof(tree, {
        vault: vault.address,
        reward: 0,
        unlockedMevReward: 1,
      }),
    })

    // small amount of shares own a lot of assets
    expect(await vault.totalAssets()).to.eq(burnedAssets.add(1))
    expect(await vault.totalSupply()).to.eq(securityDeposit.add(1))

    // user deposits
    const userAssets = parseEther('10')
    await vault.connect(holder).deposit(holder.address, ZERO_ADDRESS, { value: userAssets })

    // user lost ~ 10 gwei due to the inflation above
    expect(await vault.convertToAssets(await vault.balanceOf(holder.address))).to.eq(
      BigNumber.from('10000000980198017861')
    )
  })

  it('only vault can harvest', async () => {
    await expect(
      keeper.harvest({ rewardsRoot: ZERO_BYTES32, reward: 0, unlockedMevReward: 0, proof: [] })
    ).revertedWith('AccessDenied')
  })

  it('only mev escrow can send ether', async () => {
    await expect(vault.connect(other).receiveFromMevEscrow()).revertedWith('AccessDenied')
  })

  it('applies penalty when delta is below zero', async () => {
    const penalty = parseEther('-0.5')
    const rewardMevEscrow = parseEther('0.3')
    await setBalance(await vault.mevEscrow(), rewardMevEscrow)
    const tree = await updateRewards(keeper, [
      { vault: vault.address, reward: penalty, unlockedMevReward: rewardMevEscrow },
    ])
    const proof = getRewardsRootProof(tree, {
      vault: vault.address,
      reward: penalty,
      unlockedMevReward: rewardMevEscrow,
    })

    const totalSupplyBefore = await vault.totalSupply()
    const totalAssetsBefore = await vault.totalAssets()
    const receipt = await vault.updateState({
      rewardsRoot: tree.root,
      reward: penalty,
      unlockedMevReward: rewardMevEscrow,
      proof,
    })

    await expect(receipt)
      .emit(keeper, 'Harvested')
      .withArgs(vault.address, tree.root, penalty, rewardMevEscrow)
    await expect(receipt)
      .emit(sharedMevEscrow, 'Harvested')
      .withArgs(vault.address, rewardMevEscrow)
    expect(await waffle.provider.getBalance(vault.address)).to.be.eq(
      rewardMevEscrow.add(holderAssets).add(SECURITY_DEPOSIT)
    )
    expect(await vault.totalSupply()).to.be.eq(totalSupplyBefore)
    expect(await vault.totalAssets()).to.be.eq(totalAssetsBefore.add(penalty))
    await snapshotGasCost(receipt)
  })

  it('allocates fee to recipient when delta is above zero', async () => {
    // create vault with own mev escrow
    const vault = await createVault(
      admin,
      {
        capacity,
        feePercent,
        metadataIpfsHash,
      },
      true
    )
    await vault.connect(holder).deposit(holder.address, ZERO_ADDRESS, { value: holderAssets })
    const ownMevEscrow = await ethers.getContractFactory('OwnMevEscrow')
    const mevEscrow = ownMevEscrow.attach(await vault.mevEscrow()) as OwnMevEscrow

    const rewardValidators = parseEther('0.5')
    const rewardMevEscrow = parseEther('0.5')
    const operatorReward = parseEther('0.1')
    const reward = rewardValidators.add(rewardMevEscrow)

    await setBalance(mevEscrow.address, rewardMevEscrow)
    const tree = await updateRewards(keeper, [
      {
        vault: vault.address,
        reward: rewardValidators,
        unlockedMevReward: 0,
      },
    ])
    const proof = getRewardsRootProof(tree, {
      vault: vault.address,
      reward: rewardValidators,
      unlockedMevReward: 0,
    })

    const totalSupplyBefore = await vault.totalSupply()
    const totalAssetsBefore = await vault.totalAssets()
    const receipt = await vault.updateState({
      rewardsRoot: tree.root,
      reward: rewardValidators,
      unlockedMevReward: 0,
      proof,
    })

    const operatorShares = await vault.balanceOf(admin.address)
    expect(await vault.convertToAssets(operatorShares)).to.be.eq(operatorReward.sub(2)) // rounding error
    expect(await vault.convertToShares(operatorReward)).to.be.eq(operatorShares)
    expect(await waffle.provider.getBalance(mevEscrow.address)).to.be.eq(0)

    await expect(receipt)
      .emit(keeper, 'Harvested')
      .withArgs(vault.address, tree.root, rewardValidators, 0)
    await expect(receipt).emit(ownMevEscrow, 'Harvested').withArgs(rewardMevEscrow)
    expect(await waffle.provider.getBalance(vault.address)).to.be.eq(
      rewardMevEscrow.add(holderAssets).add(SECURITY_DEPOSIT)
    )
    expect(await vault.totalSupply()).to.be.eq(totalSupplyBefore.add(operatorShares))
    expect(await vault.totalAssets()).to.be.eq(totalAssetsBefore.add(reward))
    await snapshotGasCost(receipt)
  })

  it('updates exit queue', async () => {
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
    await vault.connect(holder).enterExitQueue(holderShares, holder.address)

    const totalSupplyBefore = await vault.totalSupply()
    const totalAssetsBefore = await vault.totalAssets()

    const rewardValidators = parseEther('0.5')
    const unlockedMevReward = parseEther('0.5')
    const reward = rewardValidators.add(unlockedMevReward)
    await setBalance(sharedMevEscrow.address, unlockedMevReward)
    const tree = await updateRewards(keeper, [
      {
        vault: vault.address,
        reward,
        unlockedMevReward,
      },
    ])
    const proof = getRewardsRootProof(tree, {
      vault: vault.address,
      reward,
      unlockedMevReward,
    })

    const receipt = await vault.updateState({
      rewardsRoot: tree.root,
      reward,
      unlockedMevReward,
      proof,
    })
    const operatorShares = await vault.balanceOf(admin.address)
    expect(await waffle.provider.getBalance(sharedMevEscrow.address)).to.be.eq(0)
    expect(await waffle.provider.getBalance(vault.address)).to.be.eq(
      unlockedMevReward.add(holderAssets).add(SECURITY_DEPOSIT)
    )
    await expect(receipt)
      .emit(keeper, 'Harvested')
      .withArgs(vault.address, tree.root, reward, unlockedMevReward)
    await expect(receipt)
      .emit(sharedMevEscrow, 'Harvested')
      .withArgs(vault.address, unlockedMevReward)
    await expect(receipt).emit(vault, 'CheckpointCreated')

    let totalSupplyAfter = totalSupplyBefore.add(operatorShares)
    let totalAssetsAfter = totalAssetsBefore.add(reward)

    const unclaimedAssets = holderAssets.add(unlockedMevReward).add(SECURITY_DEPOSIT)
    const burnedShares = unclaimedAssets.mul(totalSupplyAfter).div(totalAssetsAfter)

    totalSupplyAfter = totalSupplyAfter.sub(burnedShares)
    totalAssetsAfter = totalAssetsAfter.sub(unclaimedAssets)

    expect(await vault.totalSupply()).to.be.eq(totalSupplyAfter)
    expect(await vault.totalAssets()).to.be.eq(totalAssetsAfter)
    await snapshotGasCost(receipt)
  })
})
