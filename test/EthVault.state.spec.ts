import { ethers } from 'hardhat'
import { Contract, Signer, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { EthVault, Keeper, OwnMevEscrow__factory, SharedMevEscrow } from '../typechain-types'
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
import { extractDepositShares, setBalance } from './shared/utils'
import {
  collateralizeEthVault,
  getHarvestParams,
  getRewardsRootProof,
  updateRewards,
} from './shared/rewards'

describe('EthVault - state', () => {
  const holderAssets = ethers.parseEther('1')
  const capacity = ethers.parseEther('1000')
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'

  let holder: Wallet, admin: Signer, other: Wallet
  let vault: EthVault,
    keeper: Keeper,
    sharedMevEscrow: SharedMevEscrow,
    validatorsRegistry: Contract

  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVault']
  let createVaultMock: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVaultMock']

  beforeEach('deploy fixture', async () => {
    ;[holder, admin, other] = (await (ethers as any).getSigners()).slice(1, 4)
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
    admin = await ethers.getImpersonatedSigner(await vault.admin())
    await vault.connect(holder).deposit(holder.address, ZERO_ADDRESS, { value: holderAssets })
  })

  it('does not fail with zero assets delta', async () => {
    const vaultReward = getHarvestParams(await vault.getAddress(), 0n, 0n)
    const tree = await updateRewards(keeper, [vaultReward])
    const proof = getRewardsRootProof(tree, vaultReward)
    const receipt = await vault.updateState({
      rewardsRoot: tree.root,
      reward: vaultReward.reward,
      unlockedMevReward: vaultReward.unlockedMevReward,
      proof,
    })
    await expect(receipt)
      .to.emit(keeper, 'Harvested')
      .withArgs(await vault.getAddress(), tree.root, 0, 0)
    await expect(receipt).to.not.emit(sharedMevEscrow, 'Harvested')
  })

  it('reverts when overflow', async () => {
    const reward = (2n ** 160n - 1n) / 2n
    const unlockedMevReward = 2n ** 160n - 1n
    const tree = await updateRewards(keeper, [
      { vault: await vault.getAddress(), reward, unlockedMevReward },
    ])
    await setBalance(await sharedMevEscrow.getAddress(), unlockedMevReward)
    await expect(
      vault.updateState({
        rewardsRoot: tree.root,
        reward,
        unlockedMevReward,
        proof: getRewardsRootProof(tree, {
          vault: await vault.getAddress(),
          reward,
          unlockedMevReward,
        }),
      })
    ).revertedWithCustomError(vault, 'SafeCastOverflowedUintDowncast')
  })

  it('reverts when underflow', async () => {
    const reward = ethers.parseEther('-2')
    const tree = await updateRewards(keeper, [
      { vault: await vault.getAddress(), reward, unlockedMevReward: 0n },
    ])
    await expect(
      vault.updateState({
        rewardsRoot: tree.root,
        reward,
        unlockedMevReward: 0n,
        proof: getRewardsRootProof(tree, {
          vault: await vault.getAddress(),
          reward,
          unlockedMevReward: 0n,
        }),
      })
    ).revertedWithPanic(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
  })

  it('is not affected by inflation attack', async () => {
    const vault = await createVaultMock(
      admin as Wallet,
      {
        capacity: MAX_UINT256,
        feePercent: 0,
        metadataIpfsHash,
      },
      true
    )
    const securityDeposit = 1000000000n
    await vault.connect(other).deposit(other.address, ZERO_ADDRESS, { value: 1 })
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
    await vault._setTotalAssets(1)
    expect(await vault.totalAssets()).to.eq(1)
    expect(await vault.totalShares()).to.eq(securityDeposit + 1n)

    // attacker drops a lot of eth as a reward
    const burnedAssets = ethers.parseEther('1000')
    await setBalance(await vault.mevEscrow(), burnedAssets)

    // state is updated
    const vaultReward = getHarvestParams(await vault.getAddress(), 0n, 1n)
    const tree = await updateRewards(keeper, [vaultReward])
    await vault.updateState({
      rewardsRoot: tree.root,
      reward: vaultReward.reward,
      unlockedMevReward: vaultReward.unlockedMevReward,
      proof: getRewardsRootProof(tree, {
        vault: vaultReward.vault,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
      }),
    })

    // small amount of shares own a lot of assets
    expect(await vault.totalAssets()).to.eq(burnedAssets + 1n)
    expect(await vault.totalShares()).to.eq(securityDeposit + 1n)

    // user deposits
    const userAssets = ethers.parseEther('10')
    await vault.connect(holder).deposit(holder.address, ZERO_ADDRESS, { value: userAssets })

    // user lost ~ 10 gwei due to the inflation above
    expect(
      userAssets - (await vault.convertToAssets(await vault.getShares(holder.address)))
    ).to.be.below(10000000000)
  })

  it('only vault can harvest', async () => {
    await expect(
      keeper.harvest({ rewardsRoot: ZERO_BYTES32, reward: 0n, unlockedMevReward: 0n, proof: [] })
    ).revertedWithCustomError(keeper, 'AccessDenied')
  })

  it('only mev escrow can send ether', async () => {
    await expect(vault.connect(other).receiveFromMevEscrow()).revertedWithCustomError(
      vault,
      'AccessDenied'
    )
  })

  it('applies penalty when delta is below zero', async () => {
    const penalty = ethers.parseEther('-0.5')
    const rewardMevEscrow = ethers.parseEther('0.3')
    await setBalance(await vault.mevEscrow(), rewardMevEscrow)
    const vaultReward = getHarvestParams(await vault.getAddress(), penalty, rewardMevEscrow)
    const tree = await updateRewards(keeper, [vaultReward])
    const proof = getRewardsRootProof(tree, {
      vault: vaultReward.vault,
      reward: vaultReward.reward,
      unlockedMevReward: vaultReward.unlockedMevReward,
    })

    const totalSharesBefore = await vault.totalShares()
    const totalAssetsBefore = await vault.totalAssets()
    const balanceBefore = await ethers.provider.getBalance(await vault.getAddress())
    const receipt = await vault.updateState({
      rewardsRoot: tree.root,
      reward: vaultReward.reward,
      unlockedMevReward: vaultReward.unlockedMevReward,
      proof,
    })

    await expect(receipt)
      .emit(keeper, 'Harvested')
      .withArgs(await vault.getAddress(), tree.root, penalty, rewardMevEscrow)
    await expect(receipt)
      .emit(sharedMevEscrow, 'Harvested')
      .withArgs(await vault.getAddress(), rewardMevEscrow)
    await expect(receipt).not.emit(vault, 'FeeSharesMinted')
    expect(await ethers.provider.getBalance(await vault.getAddress())).to.be.eq(
      rewardMevEscrow + balanceBefore
    )
    expect(await vault.totalShares()).to.be.eq(totalSharesBefore)
    expect(await vault.totalAssets()).to.be.eq(totalAssetsBefore + penalty)
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
      true,
      true
    )
    await vault.connect(holder).deposit(holder.address, ZERO_ADDRESS, { value: holderAssets })

    const mevEscrow = OwnMevEscrow__factory.connect(await vault.mevEscrow(), admin)
    const rewardValidators = ethers.parseEther('0.5')
    const rewardMevEscrow = ethers.parseEther('0.5')
    const operatorReward = ethers.parseEther('0.1')
    const reward = rewardValidators + rewardMevEscrow

    await setBalance(await mevEscrow.getAddress(), rewardMevEscrow)
    const vaultReward = getHarvestParams(await vault.getAddress(), rewardValidators, 0n)
    const tree = await updateRewards(keeper, [vaultReward])
    const proof = getRewardsRootProof(tree, vaultReward)

    const totalSharesBefore = await vault.totalShares()
    const totalAssetsBefore = await vault.totalAssets()
    const receipt = await vault.updateState({
      rewardsRoot: tree.root,
      reward: vaultReward.reward,
      unlockedMevReward: vaultReward.unlockedMevReward,
      proof,
    })

    const operatorShares = await vault.getShares(await admin.getAddress())
    expect(await vault.convertToAssets(operatorShares)).to.be.eq(operatorReward - 2n) // rounding error
    expect(await vault.convertToShares(operatorReward)).to.be.eq(operatorShares)
    expect(await ethers.provider.getBalance(await mevEscrow.getAddress())).to.be.eq(0)

    await expect(receipt)
      .emit(keeper, 'Harvested')
      .withArgs(await vault.getAddress(), tree.root, rewardValidators, 0)
    await expect(receipt).emit(mevEscrow, 'Harvested').withArgs(rewardMevEscrow)
    await expect(receipt)
      .emit(vault, 'FeeSharesMinted')
      .withArgs(await admin.getAddress(), operatorShares, operatorReward)
    expect(await ethers.provider.getBalance(await vault.getAddress())).to.be.eq(
      rewardMevEscrow + holderAssets + SECURITY_DEPOSIT
    )
    expect(await vault.totalShares()).to.be.eq(totalSharesBefore + operatorShares)
    expect(await vault.totalAssets()).to.be.eq(totalAssetsBefore + reward)
    await snapshotGasCost(receipt)
  })

  it('updates exit queue', async () => {
    const vault = await createVault(
      admin,
      {
        capacity,
        feePercent,
        metadataIpfsHash,
      },
      false,
      true
    )
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
    const tx = await vault
      .connect(holder)
      .deposit(holder.address, ZERO_ADDRESS, { value: holderAssets })
    const holderShares = await extractDepositShares(tx)
    await vault.connect(holder).enterExitQueue(holderShares, holder.address)

    const totalSharesBefore = await vault.totalShares()
    const totalAssetsBefore = await vault.totalAssets()

    const rewardValidators = ethers.parseEther('0.5')
    const unlockedMevReward = ethers.parseEther('0.5')
    const reward = rewardValidators + unlockedMevReward
    await setBalance(await sharedMevEscrow.getAddress(), unlockedMevReward)
    const vaultReward = getHarvestParams(await vault.getAddress(), reward, unlockedMevReward)
    const tree = await updateRewards(keeper, [vaultReward])
    const proof = getRewardsRootProof(tree, vaultReward)

    const receipt = await vault.updateState({
      rewardsRoot: tree.root,
      reward: vaultReward.reward,
      unlockedMevReward: vaultReward.unlockedMevReward,
      proof,
    })
    const operatorShares = await vault.getShares(await admin.getAddress())
    expect(await ethers.provider.getBalance(await sharedMevEscrow.getAddress())).to.be.eq(0)
    expect(await ethers.provider.getBalance(await vault.getAddress())).to.be.eq(
      unlockedMevReward + holderAssets + SECURITY_DEPOSIT
    )
    await expect(receipt)
      .emit(keeper, 'Harvested')
      .withArgs(await vault.getAddress(), tree.root, reward, unlockedMevReward)
    await expect(receipt)
      .emit(sharedMevEscrow, 'Harvested')
      .withArgs(await vault.getAddress(), unlockedMevReward)
    await expect(receipt).emit(vault, 'CheckpointCreated')

    let totalSharesAfter = totalSharesBefore + operatorShares
    let totalAssetsAfter = totalAssetsBefore + reward

    const unclaimedAssets = holderAssets + unlockedMevReward + SECURITY_DEPOSIT
    const burnedShares = (unclaimedAssets * totalSharesAfter) / totalAssetsAfter

    totalSharesAfter = totalSharesAfter - burnedShares
    totalAssetsAfter = totalAssetsAfter - unclaimedAssets

    expect(await vault.totalShares()).to.be.eq(totalSharesAfter)
    expect(await vault.totalAssets()).to.be.eq(totalAssetsAfter)
    await snapshotGasCost(receipt)
  })
})
