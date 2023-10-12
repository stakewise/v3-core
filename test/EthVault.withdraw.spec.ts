import { ethers } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { EthVault, EthVaultMock, IKeeperRewards, Keeper, SharedMevEscrow } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import snapshotGasCost from './shared/snapshotGasCost'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import {
  EXITING_ASSETS_MIN_DELAY,
  MAX_UINT128,
  ONE_DAY,
  PANIC_CODES,
  SECURITY_DEPOSIT,
  ZERO_ADDRESS,
} from './shared/constants'
import {
  extractExitPositionTicket,
  getBlockTimestamp,
  increaseTime,
  setBalance,
} from './shared/utils'
import { collateralizeEthVault, getRewardsRootProof, updateRewards } from './shared/rewards'
import { registerEthValidator } from './shared/validators'

const validatorDeposit = ethers.parseEther('32')

describe('EthVault - withdraw', () => {
  const capacity = ethers.parseEther('1000')
  const feePercent = 1000
  const referrer = '0x' + '1'.repeat(40)
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  const holderShares = ethers.parseEther('1')
  const holderAssets = ethers.parseEther('1')

  let holder: Wallet, receiver: Wallet, admin: Wallet, other: Wallet
  let vault: EthVault,
    keeper: Keeper,
    sharedMevEscrow: SharedMevEscrow,
    validatorsRegistry: Contract

  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVault']
  let createVaultMock: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVaultMock']

  beforeEach('deploy fixture', async () => {
    ;[holder, receiver, admin, other] = (await (ethers as any).getSigners()).slice(1, 5)
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

    await vault.connect(holder).deposit(holder.address, referrer, { value: holderAssets })
  })

  describe('redeem', () => {
    it('fails with not enough balance', async () => {
      await setBalance(await vault.getAddress(), 0n)
      await expect(
        vault.connect(holder).redeem(holderShares, receiver.address)
      ).to.be.revertedWithCustomError(vault, 'InsufficientAssets')
    })

    it('fails for sender other than owner without approval', async () => {
      await expect(
        vault.connect(other).redeem(holderShares, receiver.address)
      ).to.be.revertedWithPanic(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
    })

    it('fails for shares larger than balance', async () => {
      const newBalance = holderShares + 1n
      await setBalance(await vault.getAddress(), newBalance)
      await expect(
        vault.connect(holder).redeem(newBalance, receiver.address)
      ).to.be.revertedWithPanic(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
    })

    it('fails for zero address receiver', async () => {
      const newBalance = holderShares + 1n
      await setBalance(await vault.getAddress(), newBalance)
      await expect(
        vault.connect(holder).redeem(newBalance, ZERO_ADDRESS)
      ).to.be.revertedWithCustomError(vault, 'ZeroAddress')
    })

    it('fails for zero shares', async () => {
      await expect(vault.connect(holder).redeem(0, holder.address)).to.be.revertedWithCustomError(
        vault,
        'InvalidShares'
      )
    })

    it('does not overflow', async () => {
      const vault: EthVaultMock = await createVaultMock(admin, {
        capacity,
        feePercent,
        metadataIpfsHash,
      })
      await vault.resetSecurityDeposit()
      await vault.connect(holder).deposit(holder.address, referrer, { value: holderAssets })

      const receiverBalanceBefore = await ethers.provider.getBalance(receiver.address)

      await setBalance(await vault.getAddress(), MAX_UINT128)
      await vault._setTotalAssets(MAX_UINT128)

      await vault.connect(holder).redeem(holderShares, receiver.address)
      expect(await vault.totalAssets()).to.be.eq(0)
      expect(await ethers.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore + MAX_UINT128
      )
    })

    it('fails for collateralized', async () => {
      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
      await expect(
        vault.connect(holder).redeem(holderShares, receiver.address)
      ).to.be.revertedWithCustomError(vault, 'Collateralized')
    })

    it('redeem transfers assets to receiver', async () => {
      const receiverBalanceBefore = await ethers.provider.getBalance(receiver.address)
      const receipt = await vault.connect(holder).redeem(holderShares, receiver.address)
      await expect(receipt)
        .to.emit(vault, 'Redeemed')
        .withArgs(holder.address, receiver.address, holderAssets, holderShares)

      expect(await vault.totalAssets()).to.be.eq(SECURITY_DEPOSIT)
      expect(await vault.totalShares()).to.be.eq(SECURITY_DEPOSIT)
      expect(await vault.getShares(holder.address)).to.be.eq(0)
      expect(await ethers.provider.getBalance(await vault.getAddress())).to.be.eq(SECURITY_DEPOSIT)
      expect(await ethers.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore + holderAssets
      )

      await snapshotGasCost(receipt)
    })
  })

  describe('enter exit queue', () => {
    beforeEach(async () => {
      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
    })

    it('fails with 0 shares', async () => {
      await expect(
        vault.connect(holder).enterExitQueue(0, receiver.address)
      ).to.be.revertedWithCustomError(vault, 'InvalidShares')
    })

    it('fails for zero address receiver', async () => {
      await expect(
        vault.connect(holder).enterExitQueue(holderShares, ZERO_ADDRESS)
      ).to.be.revertedWithCustomError(vault, 'ZeroAddress')
    })

    it('fails for not collateralized', async () => {
      const newVault = await createVault(admin, {
        capacity,
        feePercent,
        metadataIpfsHash,
      })
      await newVault.connect(holder).deposit(holder.address, referrer, { value: holderAssets })
      await setBalance(await vault.getAddress(), 0n)
      await expect(
        newVault.connect(holder).enterExitQueue(holderShares, receiver.address)
      ).to.be.revertedWithCustomError(vault, 'NotCollateralized')
    })

    it('fails for sender other than owner without approval', async () => {
      await expect(
        vault.connect(other).enterExitQueue(holderShares, receiver.address)
      ).to.be.revertedWithPanic(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
    })

    it('fails for shares larger than balance', async () => {
      await expect(
        vault.connect(holder).enterExitQueue(holderShares + 1n, receiver.address)
      ).to.be.revertedWithPanic(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
    })

    it('locks shares for the time of exit', async () => {
      expect(await vault.queuedShares()).to.be.eq(0)
      expect(await vault.getShares(holder.address)).to.be.eq(holderShares)
      expect(await vault.getShares(await vault.getAddress())).to.be.eq(SECURITY_DEPOSIT)

      const receipt = await vault.connect(holder).enterExitQueue(holderShares, receiver.address)
      await expect(receipt)
        .to.emit(vault, 'ExitQueueEntered')
        .withArgs(holder.address, receiver.address, validatorDeposit, holderShares)

      expect(await vault.queuedShares()).to.be.eq(holderShares)
      expect(await vault.getShares(holder.address)).to.be.eq(0)

      await snapshotGasCost(receipt)
    })
  })

  describe('update exit queue', () => {
    let harvestParams: IKeeperRewards.HarvestParamsStruct

    beforeEach(async () => {
      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
      await vault.connect(holder).enterExitQueue(holderShares, receiver.address)
      const tree = await updateRewards(keeper, [
        { vault: await vault.getAddress(), reward: 0n, unlockedMevReward: 0n },
      ])
      harvestParams = {
        rewardsRoot: tree.root,
        reward: 0n,
        unlockedMevReward: 0n,
        proof: getRewardsRootProof(tree, {
          vault: await vault.getAddress(),
          reward: 0n,
          unlockedMevReward: 0n,
        }),
      }
    })

    it('skips with 0 queued shares', async () => {
      await expect(vault.updateState(harvestParams)).to.emit(vault, 'CheckpointCreated')
      expect(await vault.queuedShares()).to.be.eq(0)
      await increaseTime(ONE_DAY)
      const tree = await updateRewards(keeper, [
        { vault: await vault.getAddress(), reward: 0n, unlockedMevReward: 0n },
      ])
      const newHarvestParams = {
        rewardsRoot: tree.root,
        reward: 0n,
        unlockedMevReward: 0n,
        proof: getRewardsRootProof(tree, {
          vault: await vault.getAddress(),
          reward: 0n,
          unlockedMevReward: 0n,
        }),
      }
      await expect(vault.updateState(newHarvestParams)).to.not.emit(vault, 'CheckpointCreated')
    })

    it('skips with 0 burned assets', async () => {
      const totalAssets = await vault.totalAssets()
      const penalty = totalAssets - totalAssets * 2n
      const tree = await updateRewards(keeper, [
        { vault: await vault.getAddress(), reward: penalty, unlockedMevReward: 0n },
      ])
      await expect(
        vault.updateState({
          rewardsRoot: tree.root,
          reward: penalty,
          unlockedMevReward: 0n,
          proof: getRewardsRootProof(tree, {
            vault: await vault.getAddress(),
            reward: penalty,
            unlockedMevReward: 0n,
          }),
        })
      ).to.not.emit(vault, 'CheckpointCreated')
    })

    it('for not all the queued shares', async () => {
      const halfHolderAssets = holderAssets / 2n
      const halfHolderShares = holderShares / 2n
      await setBalance(await vault.getAddress(), halfHolderAssets)

      const receipt = await vault.updateState(harvestParams)
      await expect(receipt)
        .to.emit(vault, 'CheckpointCreated')
        .withArgs(halfHolderShares, halfHolderAssets)
      expect(await ethers.provider.getBalance(await vault.getAddress())).to.be.eq(halfHolderAssets)
      expect(await vault.queuedShares()).to.be.eq(halfHolderShares)
      expect(await vault.getExitQueueIndex(validatorDeposit)).to.be.eq(1)

      await snapshotGasCost(receipt)
    })

    it('adds checkpoint', async () => {
      const receipt = await vault.updateState(harvestParams)
      await expect(receipt).to.emit(vault, 'CheckpointCreated').withArgs(holderShares, holderAssets)
      expect(await ethers.provider.getBalance(await vault.getAddress())).to.be.eq(
        holderAssets + SECURITY_DEPOSIT
      )
      expect(await vault.getExitQueueIndex(0)).to.be.eq(0)
      expect(await vault.totalShares()).to.be.eq(SECURITY_DEPOSIT)
      expect(await vault.totalAssets()).to.be.eq(SECURITY_DEPOSIT)
      expect(await vault.queuedShares()).to.be.eq(0)

      await snapshotGasCost(receipt)
    })
  })

  it('get checkpoint index works with many checkpoints', async () => {
    const vault: EthVaultMock = await createVaultMock(admin, {
      capacity,
      feePercent,
      metadataIpfsHash,
    })

    // collateralize vault by registering validator
    await vault.connect(holder).deposit(holder.address, referrer, { value: validatorDeposit })
    await registerEthValidator(vault, keeper, validatorsRegistry, admin)

    const receipt = await vault.connect(holder).enterExitQueue(holderShares, receiver.address)
    const positionTicket = await extractExitPositionTicket(receipt)

    // create checkpoints every day for 10 years
    for (let i = 1; i <= 3650; i++) {
      await setBalance(await vault.getAddress(), BigInt(i))
      await increaseTime(ONE_DAY)
      const rewardsTree = await updateRewards(keeper, [
        { vault: await vault.getAddress(), reward: 0n, unlockedMevReward: 0n },
      ])
      const proof = getRewardsRootProof(rewardsTree, {
        vault: await vault.getAddress(),
        reward: 0n,
        unlockedMevReward: 0n,
      })
      await expect(
        vault.updateState({
          rewardsRoot: rewardsTree.root,
          reward: 0n,
          unlockedMevReward: 0n,
          proof,
        })
      ).to.emit(vault, 'CheckpointCreated')
    }
    await snapshotGasCost(await vault.getGasCostOfGetExitQueueIndex(positionTicket))
  })

  describe('claim exited assets', () => {
    let receiverBalanceBefore: bigint
    let positionTicket: bigint
    let timestamp: number
    let harvestParams: IKeeperRewards.HarvestParamsStruct

    beforeEach(async () => {
      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
      const response = await vault.connect(holder).enterExitQueue(holderShares, receiver.address)
      positionTicket = await extractExitPositionTicket(response)
      timestamp = await getBlockTimestamp(response)
      receiverBalanceBefore = await ethers.provider.getBalance(receiver.address)

      const tree = await updateRewards(keeper, [
        { vault: await vault.getAddress(), reward: 0n, unlockedMevReward: 0n },
      ])
      harvestParams = {
        rewardsRoot: tree.root,
        reward: 0n,
        unlockedMevReward: 0n,
        proof: getRewardsRootProof(tree, {
          vault: await vault.getAddress(),
          reward: 0n,
          unlockedMevReward: 0n,
        }),
      }
    })

    it('returns zero with no queued shares', async () => {
      await increaseTime(EXITING_ASSETS_MIN_DELAY)
      await vault.updateState(harvestParams)
      const checkpointIndex = await vault.getExitQueueIndex(positionTicket)
      const result = await vault
        .connect(other)
        .claimExitedAssets.staticCall(positionTicket, timestamp, checkpointIndex)
      expect(result.newPositionTicket).to.be.eq(positionTicket)
      expect(result.claimedAssets).to.be.eq(0)
      await expect(
        vault.connect(other).claimExitedAssets(positionTicket, timestamp, checkpointIndex)
      ).to.not.emit(vault, 'ExitedAssetsClaimed')
    })

    it('returns -1 for unknown checkpoint index', async () => {
      expect(await vault.getExitQueueIndex(validatorDeposit)).to.be.eq(-1)
    })

    it('returns 0 with checkpoint index larger than checkpoints array', async () => {
      await increaseTime(EXITING_ASSETS_MIN_DELAY)
      const result = await vault
        .connect(receiver)
        .claimExitedAssets.staticCall(positionTicket, timestamp, 1)
      expect(result.newPositionTicket).to.be.eq(validatorDeposit)
      expect(result.claimedAssets).to.be.eq(0)
      expect(await ethers.provider.getBalance(receiver.address)).to.be.eq(receiverBalanceBefore)
      expect(await ethers.provider.getBalance(await vault.getAddress())).to.be.eq(
        holderAssets + SECURITY_DEPOSIT
      )
    })

    it('fails with invalid checkpoint index', async () => {
      await vault.updateState(harvestParams)
      const checkpointIndex = await vault.getExitQueueIndex(positionTicket)

      await vault.connect(holder).deposit(holder.address, referrer, { value: holderAssets * 2n })
      let response = await vault.connect(holder).enterExitQueue(holderShares, receiver.address)
      const positionTicket2 = await extractExitPositionTicket(response)
      const timestamp2 = await getBlockTimestamp(response)

      await increaseTime(EXITING_ASSETS_MIN_DELAY)

      // checkpointIndex is lower than positionTicket
      await expect(
        vault.connect(receiver).claimExitedAssets(positionTicket2, timestamp2, checkpointIndex)
      ).to.be.revertedWithCustomError(vault, 'InvalidCheckpointIndex')
      await increaseTime(ONE_DAY)
      await updateRewards(keeper, [
        { vault: await vault.getAddress(), reward: 0n, unlockedMevReward: 0n },
      ])
      await vault.updateState(harvestParams)

      response = await vault.connect(holder).enterExitQueue(holderShares, receiver.address)
      const positionTicket3 = await extractExitPositionTicket(response)
      await increaseTime(ONE_DAY)
      await updateRewards(keeper, [
        { vault: await vault.getAddress(), reward: 0n, unlockedMevReward: 0n },
      ])
      await vault.updateState(harvestParams)

      const checkpointIndexThree = await vault.getExitQueueIndex(positionTicket3)
      // checkpointIndex is higher than positionTicket
      await increaseTime(EXITING_ASSETS_MIN_DELAY)

      await expect(
        vault.connect(receiver).claimExitedAssets(positionTicket, timestamp, checkpointIndexThree)
      ).to.be.revertedWithCustomError(vault, 'InvalidCheckpointIndex')
    })

    it('fails with invalid timestamp', async () => {
      await vault.updateState(harvestParams)
      await expect(
        vault
          .connect(receiver)
          .claimExitedAssets(
            positionTicket,
            timestamp,
            await vault.getExitQueueIndex(positionTicket)
          )
      ).to.be.revertedWithCustomError(vault, 'ClaimTooEarly')
    })

    it('for single user in single checkpoint', async () => {
      await vault.updateState(harvestParams)
      const checkpointIndex = await vault.getExitQueueIndex(positionTicket)
      await increaseTime(EXITING_ASSETS_MIN_DELAY)

      const receipt = await vault
        .connect(receiver)
        .claimExitedAssets(positionTicket, timestamp, checkpointIndex)
      await expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(receiver.address, positionTicket, 0, holderAssets)
      const tx = (await receipt.wait()) as any
      const gasUsed = BigInt(tx.cumulativeGasUsed * tx.gasPrice)
      expect(await ethers.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore + holderAssets - gasUsed
      )
      expect(await ethers.provider.getBalance(await vault.getAddress())).to.be.eq(SECURITY_DEPOSIT)

      await snapshotGasCost(receipt)
    })

    it('for single user in multiple checkpoints in single transaction', async () => {
      const halfHolderAssets = holderAssets / 2n
      const halfHolderShares = holderShares / 2n

      // create two checkpoints
      await setBalance(await vault.getAddress(), halfHolderAssets)
      await expect(vault.updateState(harvestParams))
        .to.emit(vault, 'CheckpointCreated')
        .withArgs(halfHolderShares, halfHolderAssets)
      const checkpointIndex = await vault.getExitQueueIndex(positionTicket)

      await increaseTime(ONE_DAY)
      await setBalance(await vault.getAddress(), holderAssets)
      await updateRewards(keeper, [
        { vault: await vault.getAddress(), reward: 0n, unlockedMevReward: 0n },
      ])
      await expect(vault.updateState(harvestParams))
        .to.emit(vault, 'CheckpointCreated')
        .withArgs(halfHolderShares, halfHolderAssets)

      await increaseTime(EXITING_ASSETS_MIN_DELAY)
      const receipt = await vault
        .connect(receiver)
        .claimExitedAssets(positionTicket, timestamp, checkpointIndex)

      await expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(receiver.address, positionTicket, 0, holderAssets)

      const tx = (await receipt.wait()) as any
      const gasUsed = BigInt(tx.cumulativeGasUsed * tx.gasPrice)
      expect(await ethers.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore + holderAssets - gasUsed
      )
      expect(await ethers.provider.getBalance(await vault.getAddress())).to.be.eq(0)

      await snapshotGasCost(receipt)
    })

    it('for single user in multiple checkpoints in multiple transactions', async () => {
      const halfHolderAssets = holderAssets / 2n
      const halfHolderShares = holderShares / 2n

      // create first checkpoint
      await setBalance(await vault.getAddress(), halfHolderAssets)
      await expect(vault.updateState(harvestParams))
        .to.emit(vault, 'CheckpointCreated')
        .withArgs(halfHolderShares, halfHolderAssets)
      const checkpointIndex = await vault.getExitQueueIndex(positionTicket)
      await increaseTime(EXITING_ASSETS_MIN_DELAY)

      let receipt = await vault
        .connect(receiver)
        .claimExitedAssets(positionTicket, timestamp, checkpointIndex)

      const newPositionTicket = validatorDeposit + halfHolderShares
      await expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(receiver.address, positionTicket, newPositionTicket, halfHolderAssets)

      let tx = (await receipt.wait()) as any
      let gasUsed = BigInt(tx.cumulativeGasUsed * tx.gasPrice)
      expect(await ethers.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore + halfHolderAssets - gasUsed
      )

      await snapshotGasCost(receipt)

      // create second checkpoint
      await increaseTime(ONE_DAY)
      await setBalance(await vault.getAddress(), halfHolderAssets)
      await updateRewards(keeper, [
        { vault: await vault.getAddress(), reward: 0n, unlockedMevReward: 0n },
      ])
      await expect(vault.updateState(harvestParams))
        .to.emit(vault, 'CheckpointCreated')
        .withArgs(halfHolderShares, halfHolderAssets)

      const newCheckpointIndex = await vault.getExitQueueIndex(newPositionTicket)
      receipt = await vault
        .connect(receiver)
        .claimExitedAssets(newPositionTicket, timestamp, newCheckpointIndex)
      await expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(receiver.address, newPositionTicket, 0, halfHolderAssets)

      tx = (await receipt.wait()) as any
      gasUsed += BigInt(tx.cumulativeGasUsed * tx.gasPrice)
      expect(await ethers.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore + holderAssets - gasUsed
      )
      expect(await ethers.provider.getBalance(await vault.getAddress())).to.be.eq(0)

      await snapshotGasCost(receipt)
    })

    it('for multiple users in single checkpoint', async () => {
      // harvests the previous queued position
      await vault.updateState(harvestParams)
      const checkpointIndex = await vault.getExitQueueIndex(positionTicket)
      await increaseTime(EXITING_ASSETS_MIN_DELAY)
      await vault.connect(receiver).claimExitedAssets(positionTicket, timestamp, checkpointIndex)

      const shares = holderShares
      const assets = holderAssets
      const user1 = holder
      const user2 = receiver

      await vault.connect(user1).deposit(user1.address, referrer, { value: assets })
      await vault.connect(user2).deposit(user2.address, referrer, { value: assets })

      let response = await vault.connect(user1).enterExitQueue(shares, user1.address)
      const user1PositionTicket = await extractExitPositionTicket(response)
      const user1Timestamp = await getBlockTimestamp(response)
      const user1BalanceBefore = await ethers.provider.getBalance(user1.address)

      response = await vault.connect(user2).enterExitQueue(shares, user2.address)
      const user2PositionTicket = await extractExitPositionTicket(response)
      const user2Timestamp = await getBlockTimestamp(response)
      const user2BalanceBefore = await ethers.provider.getBalance(user2.address)

      await increaseTime(ONE_DAY)
      await updateRewards(keeper, [
        { vault: await vault.getAddress(), reward: 0n, unlockedMevReward: 0n },
      ])
      await expect(vault.connect(other).updateState(harvestParams))
        .to.emit(vault, 'CheckpointCreated')
        .withArgs(shares * 2n, assets * 2n)
      await increaseTime(EXITING_ASSETS_MIN_DELAY)

      response = await vault
        .connect(user2)
        .claimExitedAssets(
          user2PositionTicket,
          user2Timestamp,
          await vault.getExitQueueIndex(user2PositionTicket)
        )
      await expect(response)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(user2.address, user2PositionTicket, 0, assets)

      let tx = (await response.wait()) as any
      let gasUsed = BigInt(tx.cumulativeGasUsed * tx.gasPrice)
      expect(await ethers.provider.getBalance(user2.address)).to.be.eq(
        user2BalanceBefore + assets - gasUsed
      )

      response = await vault
        .connect(user1)
        .claimExitedAssets(
          user1PositionTicket,
          user1Timestamp,
          await vault.getExitQueueIndex(user1PositionTicket)
        )
      await expect(response)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(user1.address, user1PositionTicket, 0, assets)

      tx = (await response.wait()) as any
      gasUsed = BigInt(tx.cumulativeGasUsed * tx.gasPrice)
      expect(await ethers.provider.getBalance(user1.address)).to.be.eq(
        user1BalanceBefore + assets - gasUsed
      )
      expect(await ethers.provider.getBalance(await vault.getAddress())).to.be.eq(SECURITY_DEPOSIT)
    })
  })

  /// Scenario inspired by solmate ERC4626 tests:
  /// https://github.com/transmissions11/solmate/blob/main/src/test/ERC4626.t.sol
  it('multiple deposits and withdrawals', async () => {
    const vault = await createVaultMock(admin, {
      capacity,
      feePercent: 0,
      metadataIpfsHash,
    })
    await vault.resetSecurityDeposit()
    const alice = holder
    const bob = other

    // collateralize vault by registering validator
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
    await vault._setTotalAssets(0)
    await vault._setTotalShares(0)

    let aliceShares = 0n
    let aliceAssets = 0n
    let bobShares = 0n
    let bobAssets = 0n
    let totalAssets = 0n
    let totalShares = 0n
    let queuedShares = 0n
    let unclaimedAssets = 0n
    let latestPositionTicket = validatorDeposit
    let vaultLiquidAssets = 0n
    let totalReward = 0n
    let totalUnlockedMevReward = 0n

    const checkVaultState = async () => {
      expect(await vault.getShares(alice.address)).to.be.eq(aliceShares)
      expect(await vault.getShares(bob.address)).to.be.eq(bobShares)
      expect(await vault.convertToAssets(aliceShares)).to.be.eq(aliceAssets)
      expect(await vault.convertToAssets(bobShares)).to.be.eq(bobAssets)
      expect(await vault.totalShares()).to.be.eq(totalShares)
      expect(await ethers.provider.getBalance(await sharedMevEscrow.getAddress())).to.be.eq(0)
      expect(await ethers.provider.getBalance(await vault.getAddress())).to.be.eq(vaultLiquidAssets)
      expect(await vault.totalAssets()).to.be.eq(totalAssets)
      expect(await vault.queuedShares()).to.be.eq(queuedShares)
    }

    // 1. Alice deposits 2000 ETH (mints 2000 shares)
    aliceShares += 2000n
    aliceAssets += 2000n
    totalAssets += 2000n
    vaultLiquidAssets += 2000n
    totalShares += 2000n
    await vault.connect(alice).deposit(alice.address, referrer, { value: aliceAssets })

    await checkVaultState()

    // 2. Bob deposits 4000 ETH (mints 4000 shares)
    bobShares += 4000n
    bobAssets += 4000n
    totalAssets += 4000n
    vaultLiquidAssets += 4000n
    totalShares += 4000n
    await vault.connect(bob).deposit(bob.address, referrer, { value: bobAssets })

    await checkVaultState()

    // 3. Vault mutates by +3000 ETH (40% from validators, 60% from priority fees)
    totalAssets += 3000n
    totalReward += 3000n
    vaultLiquidAssets += 1800n
    totalUnlockedMevReward += 1800n
    let tree = await updateRewards(keeper, [
      {
        vault: await vault.getAddress(),
        reward: totalReward,
        unlockedMevReward: totalUnlockedMevReward,
      },
    ])
    let proof = getRewardsRootProof(tree, {
      vault: await vault.getAddress(),
      reward: totalReward,
      unlockedMevReward: totalUnlockedMevReward,
    })
    await setBalance(await sharedMevEscrow.getAddress(), 1800n)
    await vault.updateState({
      rewardsRoot: tree.root,
      reward: totalReward,
      unlockedMevReward: totalUnlockedMevReward,
      proof,
    })
    aliceAssets += 1000n
    bobAssets += 2000n

    await checkVaultState()

    // 4. Alice deposits 2000 ETH (mints 1334 shares)
    aliceShares += 1334n
    aliceAssets += 2000n
    bobAssets -= 1n // rounding error
    totalAssets += 2000n
    vaultLiquidAssets += 2000n
    totalShares += 1334n

    await vault.connect(alice).deposit(alice.address, referrer, { value: 2000 })
    await checkVaultState()

    // 5. Bob deposits 3000 ETH (mints 2000 shares)
    await vault.connect(bob).deposit(bob.address, referrer, { value: 3000 })
    bobShares += 2001n // rounds up
    bobAssets += 3000n
    totalAssets += 3000n
    vaultLiquidAssets += 3000n
    totalShares += 2001n

    await checkVaultState()

    // 6. Vault mutates by +3000 shares
    totalAssets += 3000n
    totalReward += 3000n
    vaultLiquidAssets += 1800n
    totalUnlockedMevReward += 1800n
    await setBalance(await sharedMevEscrow.getAddress(), 1800n)
    tree = await updateRewards(keeper, [
      {
        vault: await vault.getAddress(),
        reward: totalReward,
        unlockedMevReward: totalUnlockedMevReward,
      },
    ])
    proof = getRewardsRootProof(tree, {
      vault: await vault.getAddress(),
      reward: totalReward,
      unlockedMevReward: totalUnlockedMevReward,
    })
    await vault.updateState({
      rewardsRoot: tree.root,
      reward: totalReward,
      unlockedMevReward: totalUnlockedMevReward,
      proof,
    })

    aliceAssets += 1071n
    bobAssets += 1929n

    await checkVaultState()

    // 7. Alice enters exit queue with 1333 shares (2427 assets)
    let response = await vault.connect(alice).enterExitQueue(1333, alice.address)
    let alicePositionTicket = await extractExitPositionTicket(response)
    let aliceTimestamp = await getBlockTimestamp(response)

    // alice withdraws assets
    await updateRewards(keeper, [
      {
        vault: await vault.getAddress(),
        reward: totalReward,
        unlockedMevReward: totalUnlockedMevReward,
      },
    ])
    await vault.updateState({
      rewardsRoot: tree.root,
      reward: totalReward,
      unlockedMevReward: totalUnlockedMevReward,
      proof,
    })
    await increaseTime(EXITING_ASSETS_MIN_DELAY)
    await vault
      .connect(alice)
      .claimExitedAssets(
        alicePositionTicket,
        aliceTimestamp,
        await vault.getExitQueueIndex(alicePositionTicket)
      )

    aliceShares -= 1333n
    aliceAssets -= 2428n
    bobAssets -= 1n // rounding error
    totalAssets -= 2427n
    vaultLiquidAssets -= 2427n
    totalShares -= 1332n
    expect(alicePositionTicket).to.eq(latestPositionTicket)
    latestPositionTicket = validatorDeposit + 1333n
    queuedShares += 1n

    await checkVaultState()

    // 8. Bob enters exit queue with 1608 assets (2928 shares)
    response = await vault.connect(bob).enterExitQueue(1608, bob.address)
    let bobPositionTicket = await extractExitPositionTicket(response)
    let bobTimestamp = await getBlockTimestamp(response)

    await updateRewards(keeper, [
      {
        vault: await vault.getAddress(),
        reward: totalReward,
        unlockedMevReward: totalUnlockedMevReward,
      },
    ])
    await vault.updateState({
      rewardsRoot: tree.root,
      reward: totalReward,
      unlockedMevReward: totalUnlockedMevReward,
      proof,
    })
    await increaseTime(EXITING_ASSETS_MIN_DELAY)
    await vault
      .connect(alice)
      .claimExitedAssets(
        alicePositionTicket,
        aliceTimestamp,
        await vault.getExitQueueIndex(alicePositionTicket)
      )
    await vault
      .connect(bob)
      .claimExitedAssets(
        bobPositionTicket,
        bobTimestamp,
        await vault.getExitQueueIndex(bobPositionTicket)
      )

    bobShares -= 1608n
    bobAssets -= 2929n
    totalAssets -= 2929n
    vaultLiquidAssets -= 2927n
    totalShares -= 1608n
    expect(bobPositionTicket).to.eq(latestPositionTicket)
    latestPositionTicket = latestPositionTicket + 1608n

    await checkVaultState()

    // 9. Most the Vault's assets are staked
    vaultLiquidAssets = 2600n
    await setBalance(await vault.getAddress(), 2600n)

    // 10. Alice enters exit queue with 1000 shares
    response = await vault.connect(alice).enterExitQueue(1000, alice.address)
    alicePositionTicket = await extractExitPositionTicket(response)
    aliceTimestamp = await getBlockTimestamp(response)
    await expect(response)
      .to.emit(vault, 'ExitQueueEntered')
      .withArgs(alice.address, alice.address, alicePositionTicket, 1000)

    aliceShares -= 1000n // rounding error
    aliceAssets -= 1821n
    queuedShares += 1000n
    expect(alicePositionTicket).to.eq(latestPositionTicket)
    latestPositionTicket = latestPositionTicket + 1000n

    await checkVaultState()

    // 11. Bob enters exit queue with 4393 shares
    response = await vault.connect(bob).enterExitQueue(4393n, bob.address)
    bobPositionTicket = await extractExitPositionTicket(response)
    bobTimestamp = await getBlockTimestamp(response)

    await expect(response)
      .to.emit(vault, 'ExitQueueEntered')
      .withArgs(bob.address, bob.address, bobPositionTicket, 4393)

    bobShares -= 4393n
    bobAssets -= 7998n
    queuedShares += 4393n
    expect(bobPositionTicket).to.eq(latestPositionTicket)
    latestPositionTicket = latestPositionTicket + 4393n

    await checkVaultState()

    // 12. Update exit queue and transfer not staked assets to Bob and Alice
    await updateRewards(keeper, [
      {
        vault: await vault.getAddress(),
        reward: totalReward,
        unlockedMevReward: totalUnlockedMevReward,
      },
    ])
    await expect(
      vault.updateState({
        rewardsRoot: tree.root,
        reward: totalReward,
        unlockedMevReward: totalUnlockedMevReward,
        proof,
      })
    )
      .to.emit(vault, 'CheckpointCreated')
      .withArgs(1426, 2598)

    totalAssets -= 2598n
    totalShares -= 1426n
    queuedShares -= 1426n
    unclaimedAssets += 2598n
    await checkVaultState()

    // 13. Vault mutates by +5000 shares
    totalAssets += 5000n
    totalReward += 5000n
    vaultLiquidAssets += 3000n
    totalUnlockedMevReward += 3000n

    tree = await updateRewards(keeper, [
      {
        vault: await vault.getAddress(),
        reward: totalReward,
        unlockedMevReward: totalUnlockedMevReward,
      },
    ])
    await setBalance(await sharedMevEscrow.getAddress(), 3000n)
    await expect(
      vault.updateState({
        rewardsRoot: tree.root,
        reward: totalReward,
        unlockedMevReward: totalUnlockedMevReward,
        proof: getRewardsRootProof(tree, {
          vault: await vault.getAddress(),
          reward: totalReward,
          unlockedMevReward: totalUnlockedMevReward,
        }),
      })
    )
      .to.emit(vault, 'CheckpointCreated')
      .withArgs(1061, 3000)

    // update alice assets
    aliceAssets += 1007n
    totalShares -= 1061n
    totalAssets -= 3000n
    queuedShares -= 1061n
    unclaimedAssets += 3000n
    await checkVaultState()

    // 14. Bob claims exited assets
    let bobCheckpointIdx = await vault.getExitQueueIndex(bobPositionTicket)
    await expect(
      vault.connect(bob).claimExitedAssets(bobPositionTicket, bobTimestamp, bobCheckpointIdx)
    )
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(bob.address, bobPositionTicket, bobPositionTicket + 1486n, 3774n)

    bobPositionTicket = bobPositionTicket + 1486n
    vaultLiquidAssets -= 3774n
    unclaimedAssets -= 3774n
    await checkVaultState()

    // 15. Alice claims exited assets
    let aliceCheckpointIdx = await vault.getExitQueueIndex(alicePositionTicket)
    await expect(
      vault
        .connect(alice)
        .claimExitedAssets(alicePositionTicket, aliceTimestamp, aliceCheckpointIdx)
    )
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(alice.address, alicePositionTicket, 0, 1821)

    vaultLiquidAssets -= 1821n
    unclaimedAssets -= 1821n
    await checkVaultState()

    // 16. Alice enters exit queue with 1001 shares
    response = await vault.connect(alice).enterExitQueue(1001, alice.address)
    alicePositionTicket = await extractExitPositionTicket(response)
    aliceTimestamp = await getBlockTimestamp(response)
    await expect(response)
      .to.emit(vault, 'ExitQueueEntered')
      .withArgs(alice.address, alice.address, alicePositionTicket, 1001)

    expect(alicePositionTicket).to.be.eq(latestPositionTicket)
    queuedShares += 1001n
    aliceShares -= 1001n
    aliceAssets -= 2829n
    await checkVaultState()

    // 17. Withdrawal of all the assets arrives
    await increaseTime(ONE_DAY)
    await setBalance(await vault.getAddress(), totalAssets + unclaimedAssets + 2n)
    await updateRewards(keeper, [
      {
        vault: await vault.getAddress(),
        reward: totalReward,
        unlockedMevReward: totalUnlockedMevReward,
      },
    ])
    await expect(
      vault.updateState({
        rewardsRoot: tree.root,
        reward: totalReward,
        unlockedMevReward: totalUnlockedMevReward,
        proof,
      })
    ).to.emit(vault, 'CheckpointCreated')

    unclaimedAssets += totalAssets + 2n
    vaultLiquidAssets = unclaimedAssets
    totalShares = 0n
    queuedShares = 0n
    totalAssets = 0n

    await checkVaultState()

    // 18. Bob claims exited assets
    bobCheckpointIdx = await vault.getExitQueueIndex(bobPositionTicket)
    expect(bobCheckpointIdx).to.eq(5)
    await expect(
      vault.connect(bob).claimExitedAssets(bobPositionTicket, bobTimestamp, bobCheckpointIdx)
    )
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(bob.address, bobPositionTicket, 0, 8216)

    vaultLiquidAssets -= 8216n
    await checkVaultState()

    // 19. Alice claims exited assets
    aliceCheckpointIdx = await vault.getExitQueueIndex(alicePositionTicket)
    expect(aliceCheckpointIdx).to.eq(5)
    await expect(
      vault
        .connect(alice)
        .claimExitedAssets(alicePositionTicket, aliceTimestamp, aliceCheckpointIdx)
    )
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(alice.address, alicePositionTicket, 0, 2829)
    vaultLiquidAssets -= 2829n
    await checkVaultState()

    // 20. Check whether state is correct
    aliceShares = 0n
    aliceAssets = 0n
    bobShares = 0n
    bobAssets = 0n
    totalAssets = 0n
    totalShares = 0n
    queuedShares = 0n
    vaultLiquidAssets = 6n
    await checkVaultState()
  })
})
