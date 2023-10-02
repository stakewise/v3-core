import { ethers, waffle } from 'hardhat'
import { BigNumber, Contract, Wallet } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import { EthVault, EthVaultMock, IKeeperRewards, Keeper, SharedMevEscrow } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import snapshotGasCost from './shared/snapshotGasCost'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import {
  MAX_UINT128,
  ONE_DAY,
  PANIC_CODES,
  SECURITY_DEPOSIT,
  ZERO_ADDRESS,
} from './shared/constants'
import { increaseTime, setBalance } from './shared/utils'
import { collateralizeEthVault, getRewardsRootProof, updateRewards } from './shared/rewards'
import { registerEthValidator } from './shared/validators'

const createFixtureLoader = waffle.createFixtureLoader
const validatorDeposit = parseEther('32')

describe('EthVault - withdraw', () => {
  const capacity = parseEther('1000')
  const feePercent = 1000
  const referrer = '0x' + '1'.repeat(40)
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  const holderShares = parseEther('1')
  const holderAssets = parseEther('1')

  let holder: Wallet, receiver: Wallet, admin: Wallet, dao: Wallet, other: Wallet
  let vault: EthVault,
    keeper: Keeper,
    sharedMevEscrow: SharedMevEscrow,
    validatorsRegistry: Contract

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVault']
  let createVaultMock: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVaultMock']

  before('create fixture loader', async () => {
    ;[holder, receiver, dao, admin, other] = await (ethers as any).getSigners()
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

    // collateralize vault
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
    await vault.connect(holder).deposit(holder.address, referrer, { value: holderAssets })
  })

  describe('redeem', () => {
    it('fails with not enough balance', async () => {
      await setBalance(vault.address, BigNumber.from(0))
      await expect(vault.connect(holder).redeem(holderShares, receiver.address)).to.be.revertedWith(
        'InsufficientAssets'
      )
    })

    it('fails for sender other than owner without approval', async () => {
      await expect(vault.connect(other).redeem(holderShares, receiver.address)).to.be.revertedWith(
        PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW
      )
    })

    it('fails for shares larger than balance', async () => {
      const newBalance = holderShares.add(1)
      await setBalance(vault.address, newBalance)
      await expect(vault.connect(holder).redeem(newBalance, receiver.address)).to.be.revertedWith(
        PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW
      )
    })

    it('fails for zero address receiver', async () => {
      const newBalance = holderShares.add(1)
      await setBalance(vault.address, newBalance)
      await expect(vault.connect(holder).redeem(newBalance, ZERO_ADDRESS)).to.be.revertedWith(
        'ZeroAddress'
      )
    })

    it('fails for not harvested vault', async () => {
      await updateRewards(keeper, [{ vault: vault.address, reward: 1, unlockedMevReward: 0 }])
      await updateRewards(keeper, [{ vault: vault.address, reward: 2, unlockedMevReward: 0 }])
      await expect(vault.connect(holder).redeem(holderShares, receiver.address)).to.be.revertedWith(
        'NotHarvested'
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

      const receiverBalanceBefore = await waffle.provider.getBalance(receiver.address)

      await setBalance(await vault.address, MAX_UINT128)
      await vault._setTotalAssets(MAX_UINT128)

      await vault.connect(holder).redeem(holderShares, receiver.address)
      expect(await vault.totalAssets()).to.be.eq(0)
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore.add(MAX_UINT128)
      )
    })

    it('redeem transfers assets to receiver', async () => {
      const receiverBalanceBefore = await waffle.provider.getBalance(receiver.address)
      const receipt = await vault.connect(holder).redeem(holderShares, receiver.address)
      await expect(receipt)
        .to.emit(vault, 'Redeemed')
        .withArgs(holder.address, receiver.address, holderAssets, holderShares)

      expect(await vault.totalAssets()).to.be.eq(SECURITY_DEPOSIT)
      expect(await vault.totalShares()).to.be.eq(SECURITY_DEPOSIT)
      expect(await vault.getShares(holder.address)).to.be.eq(0)
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(SECURITY_DEPOSIT)
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore.add(holderAssets)
      )

      await snapshotGasCost(receipt)
    })

    it('fails with 0 shares', async () => {
      await expect(vault.connect(holder).redeem(0, receiver.address)).to.be.revertedWith(
        'InvalidShares'
      )
    })
  })

  describe('enter exit queue', () => {
    it('fails with 0 shares', async () => {
      await expect(vault.connect(holder).enterExitQueue(0, receiver.address)).to.be.revertedWith(
        'InvalidShares'
      )
    })

    it('fails for zero address receiver', async () => {
      await expect(
        vault.connect(holder).enterExitQueue(holderShares, ZERO_ADDRESS)
      ).to.be.revertedWith('ZeroAddress')
    })

    it('fails for not collateralized', async () => {
      const newVault = await createVault(admin, {
        capacity,
        feePercent,
        metadataIpfsHash,
      })
      await newVault.connect(holder).deposit(holder.address, referrer, { value: holderAssets })
      await expect(
        newVault.connect(holder).enterExitQueue(holderShares, receiver.address)
      ).to.be.revertedWith('NotCollateralized')
    })

    it('fails for sender other than owner without approval', async () => {
      await expect(
        vault.connect(other).enterExitQueue(holderShares, receiver.address)
      ).to.be.revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
    })

    it('fails for shares larger than balance', async () => {
      await expect(
        vault.connect(holder).enterExitQueue(holderShares.add(1), receiver.address)
      ).to.be.revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
    })

    it('locks shares for the time of exit', async () => {
      expect(await vault.queuedShares()).to.be.eq(0)
      expect(await vault.getShares(holder.address)).to.be.eq(holderShares)
      expect(await vault.getShares(vault.address)).to.be.eq(SECURITY_DEPOSIT)

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
      await vault.connect(holder).enterExitQueue(holderShares, receiver.address)
      const tree = await updateRewards(keeper, [
        { vault: vault.address, reward: 0, unlockedMevReward: 0 },
      ])
      harvestParams = {
        rewardsRoot: tree.root,
        reward: 0,
        unlockedMevReward: 0,
        proof: getRewardsRootProof(tree, {
          vault: vault.address,
          reward: 0,
          unlockedMevReward: 0,
        }),
      }
    })

    it('skips with 0 queued shares', async () => {
      await expect(vault.updateState(harvestParams)).to.emit(vault, 'CheckpointCreated')
      expect(await vault.queuedShares()).to.be.eq(0)
      await increaseTime(ONE_DAY)
      const tree = await updateRewards(keeper, [
        { vault: vault.address, reward: 0, unlockedMevReward: 0 },
      ])
      const newHarvestParams = {
        rewardsRoot: tree.root,
        reward: 0,
        unlockedMevReward: 0,
        proof: getRewardsRootProof(tree, {
          vault: vault.address,
          reward: 0,
          unlockedMevReward: 0,
        }),
      }
      await expect(vault.updateState(newHarvestParams)).to.not.emit(vault, 'CheckpointCreated')
    })

    it('skips with 0 burned assets', async () => {
      const totalAssets = await vault.totalAssets()
      const penalty = totalAssets.sub(totalAssets.mul(2))
      const tree = await updateRewards(keeper, [
        { vault: vault.address, reward: penalty, unlockedMevReward: 0 },
      ])
      await expect(
        vault.updateState({
          rewardsRoot: tree.root,
          reward: penalty,
          unlockedMevReward: 0,
          proof: getRewardsRootProof(tree, {
            vault: vault.address,
            reward: penalty,
            unlockedMevReward: 0,
          }),
        })
      ).to.not.emit(vault, 'CheckpointCreated')
    })

    it('for not all the queued shares', async () => {
      const halfHolderAssets = holderAssets.div(2)
      const halfHolderShares = holderShares.div(2)
      await setBalance(vault.address, halfHolderAssets)

      const receipt = await vault.updateState(harvestParams)
      await expect(receipt)
        .to.emit(vault, 'CheckpointCreated')
        .withArgs(halfHolderShares, halfHolderAssets)
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(halfHolderAssets)
      expect(await vault.queuedShares()).to.be.eq(halfHolderShares)
      expect(await vault.getExitQueueIndex(validatorDeposit)).to.be.eq(1)

      await snapshotGasCost(receipt)
    })

    it('adds checkpoint', async () => {
      const receipt = await vault.updateState(harvestParams)
      await expect(receipt).to.emit(vault, 'CheckpointCreated').withArgs(holderShares, holderAssets)
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(
        holderAssets.add(SECURITY_DEPOSIT)
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

    const positionTicket = await vault
      .connect(holder)
      .callStatic.enterExitQueue(holderShares, receiver.address)
    await vault.connect(holder).enterExitQueue(holderShares, receiver.address)

    // create checkpoints every day for 10 years
    for (let i = 1; i <= 3650; i++) {
      await setBalance(vault.address, BigNumber.from(i))
      await increaseTime(ONE_DAY)
      const rewardsTree = await updateRewards(keeper, [
        { vault: vault.address, reward: 0, unlockedMevReward: 0 },
      ])
      const proof = getRewardsRootProof(rewardsTree, {
        vault: vault.address,
        reward: 0,
        unlockedMevReward: 0,
      })
      await expect(
        vault.updateState({
          rewardsRoot: rewardsTree.root,
          reward: 0,
          unlockedMevReward: 0,
          proof,
        })
      ).to.emit(vault, 'CheckpointCreated')
    }
    await snapshotGasCost(await vault.getGasCostOfGetExitQueueIndex(positionTicket))
  })

  describe('claim exited assets', () => {
    let receiverBalanceBefore: BigNumber
    let positionTicket: BigNumber
    let harvestParams: IKeeperRewards.HarvestParamsStruct

    beforeEach(async () => {
      positionTicket = await vault
        .connect(holder)
        .callStatic.enterExitQueue(holderShares, receiver.address)
      await vault.connect(holder).enterExitQueue(holderShares, receiver.address)
      receiverBalanceBefore = await waffle.provider.getBalance(receiver.address)

      const tree = await updateRewards(keeper, [
        { vault: vault.address, reward: 0, unlockedMevReward: 0 },
      ])
      harvestParams = {
        rewardsRoot: tree.root,
        reward: 0,
        unlockedMevReward: 0,
        proof: getRewardsRootProof(tree, {
          vault: vault.address,
          reward: 0,
          unlockedMevReward: 0,
        }),
      }
    })

    it('returns zero with no queued shares', async () => {
      await vault.updateState(harvestParams)
      const checkpointIndex = await vault.getExitQueueIndex(positionTicket)
      const result = await vault
        .connect(other)
        .callStatic.claimExitedAssets(positionTicket, checkpointIndex)
      expect(result.newPositionTicket).to.be.eq(positionTicket)
      expect(result.claimedAssets).to.be.eq(0)
      await expect(
        vault.connect(other).claimExitedAssets(positionTicket, checkpointIndex)
      ).to.not.emit(vault, 'ExitedAssetsClaimed')
    })

    it('returns -1 for unknown checkpoint index', async () => {
      expect(await vault.getExitQueueIndex(validatorDeposit)).to.be.eq(-1)
    })

    it('returns 0 with checkpoint index larger than checkpoints array', async () => {
      const result = await vault.connect(receiver).callStatic.claimExitedAssets(positionTicket, 1)
      expect(result.newPositionTicket).to.be.eq(validatorDeposit)
      expect(result.claimedAssets).to.be.eq(0)
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(receiverBalanceBefore)
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(
        holderAssets.add(SECURITY_DEPOSIT)
      )
    })

    it('fails with invalid checkpoint index', async () => {
      await vault.updateState(harvestParams)
      const checkpointIndex = await vault.getExitQueueIndex(positionTicket)

      await vault.connect(holder).deposit(holder.address, referrer, { value: holderAssets.mul(2) })
      const positionTicket2 = await vault
        .connect(holder)
        .callStatic.enterExitQueue(holderShares, receiver.address)
      await vault.connect(holder).enterExitQueue(holderShares, receiver.address)
      // checkpointIndex is lower than positionTicket
      await expect(
        vault.connect(receiver).claimExitedAssets(positionTicket2, checkpointIndex)
      ).to.be.revertedWith('InvalidCheckpointIndex')
      await increaseTime(ONE_DAY)
      await updateRewards(keeper, [{ vault: vault.address, reward: 0, unlockedMevReward: 0 }])
      await vault.updateState(harvestParams)

      const positionTicket3 = await vault
        .connect(holder)
        .callStatic.enterExitQueue(holderShares, receiver.address)
      await vault.connect(holder).enterExitQueue(holderShares, receiver.address)
      await increaseTime(ONE_DAY)
      await updateRewards(keeper, [{ vault: vault.address, reward: 0, unlockedMevReward: 0 }])
      await vault.updateState(harvestParams)
      const checkpointIndexThree = await vault.getExitQueueIndex(positionTicket3)
      // checkpointIndex is higher than positionTicket
      await expect(
        vault.connect(receiver).claimExitedAssets(positionTicket, checkpointIndexThree)
      ).to.be.revertedWith('InvalidCheckpointIndex')
    })

    it('for single user in single checkpoint', async () => {
      await vault.updateState(harvestParams)
      const checkpointIndex = await vault.getExitQueueIndex(positionTicket)

      const receipt = await vault
        .connect(receiver)
        .claimExitedAssets(positionTicket, checkpointIndex)
      await expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(receiver.address, positionTicket, 0, holderAssets)
      const tx = await receipt.wait()
      const gasUsed = tx.effectiveGasPrice.mul(tx.cumulativeGasUsed)
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore.add(holderAssets).sub(gasUsed)
      )
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(SECURITY_DEPOSIT)

      await snapshotGasCost(receipt)
    })

    it('for single user in multiple checkpoints in single transaction', async () => {
      const halfHolderAssets = holderAssets.div(2)
      const halfHolderShares = holderShares.div(2)

      // create two checkpoints
      await setBalance(vault.address, halfHolderAssets)
      await expect(vault.updateState(harvestParams))
        .to.emit(vault, 'CheckpointCreated')
        .withArgs(halfHolderShares, halfHolderAssets)
      const checkpointIndex = await vault.getExitQueueIndex(positionTicket)

      await increaseTime(ONE_DAY)
      await setBalance(vault.address, holderAssets)
      await updateRewards(keeper, [{ vault: vault.address, reward: 0, unlockedMevReward: 0 }])
      await expect(vault.updateState(harvestParams))
        .to.emit(vault, 'CheckpointCreated')
        .withArgs(halfHolderShares, halfHolderAssets)

      const receipt = await vault
        .connect(receiver)
        .claimExitedAssets(positionTicket, checkpointIndex)

      await expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(receiver.address, positionTicket, 0, holderAssets)

      const tx = await receipt.wait()
      const gasUsed = tx.effectiveGasPrice.mul(tx.cumulativeGasUsed)
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore.add(holderAssets).sub(gasUsed)
      )
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(0)

      await snapshotGasCost(receipt)
    })

    it('for single user in multiple checkpoints in multiple transactions', async () => {
      const halfHolderAssets = holderAssets.div(2)
      const halfHolderShares = holderShares.div(2)

      // create first checkpoint
      await setBalance(vault.address, halfHolderAssets)
      await expect(vault.updateState(harvestParams))
        .to.emit(vault, 'CheckpointCreated')
        .withArgs(halfHolderShares, halfHolderAssets)
      const checkpointIndex = await vault.getExitQueueIndex(positionTicket)
      let receipt = await vault.connect(receiver).claimExitedAssets(positionTicket, checkpointIndex)

      const newPositionTicket = validatorDeposit.add(halfHolderShares)
      await expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(receiver.address, positionTicket, newPositionTicket, halfHolderAssets)

      let tx = await receipt.wait()
      let gasUsed = tx.effectiveGasPrice.mul(tx.cumulativeGasUsed)
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore.add(halfHolderAssets).sub(gasUsed)
      )

      await snapshotGasCost(receipt)

      // create second checkpoint
      await increaseTime(ONE_DAY)
      await setBalance(vault.address, halfHolderAssets)
      await updateRewards(keeper, [{ vault: vault.address, reward: 0, unlockedMevReward: 0 }])
      await expect(vault.updateState(harvestParams))
        .to.emit(vault, 'CheckpointCreated')
        .withArgs(halfHolderShares, halfHolderAssets)

      const newCheckpointIndex = await vault.getExitQueueIndex(newPositionTicket)
      receipt = await vault
        .connect(receiver)
        .claimExitedAssets(newPositionTicket, newCheckpointIndex)
      await expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(receiver.address, newPositionTicket, 0, halfHolderAssets)

      tx = await receipt.wait()
      gasUsed = gasUsed.add(tx.effectiveGasPrice.mul(tx.cumulativeGasUsed))
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore.add(holderAssets).sub(gasUsed)
      )
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(0)

      await snapshotGasCost(receipt)
    })

    it('for multiple users in single checkpoint', async () => {
      // harvests the previous queued position
      await vault.updateState(harvestParams)
      const checkpointIndex = await vault.getExitQueueIndex(positionTicket)
      await vault.connect(receiver).claimExitedAssets(positionTicket, checkpointIndex)

      const shares = holderShares
      const assets = holderAssets
      const user1 = holder
      const user2 = receiver

      await vault.connect(user1).deposit(user1.address, referrer, { value: assets })
      await vault.connect(user2).deposit(user2.address, referrer, { value: assets })

      const user1PositionTicket = await vault
        .connect(user1)
        .callStatic.enterExitQueue(shares, user1.address)
      await vault.connect(user1).enterExitQueue(shares, user1.address)
      const user1BalanceBefore = await waffle.provider.getBalance(user1.address)

      const user2PositionTicket = await vault
        .connect(user2)
        .callStatic.enterExitQueue(shares, user2.address)
      await vault.connect(user2).enterExitQueue(shares, user2.address)
      const user2BalanceBefore = await waffle.provider.getBalance(user2.address)

      await increaseTime(ONE_DAY)
      await updateRewards(keeper, [{ vault: vault.address, reward: 0, unlockedMevReward: 0 }])
      await expect(vault.connect(other).updateState(harvestParams))
        .to.emit(vault, 'CheckpointCreated')
        .withArgs(shares.mul(2), assets.mul(2))

      let receipt = await vault
        .connect(user2)
        .claimExitedAssets(user2PositionTicket, await vault.getExitQueueIndex(user2PositionTicket))
      await expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(user2.address, user2PositionTicket, 0, assets)

      let tx = await receipt.wait()
      let gasUsed = tx.effectiveGasPrice.mul(tx.cumulativeGasUsed)
      expect(await waffle.provider.getBalance(user2.address)).to.be.eq(
        user2BalanceBefore.add(assets).sub(gasUsed)
      )

      receipt = await vault
        .connect(user1)
        .claimExitedAssets(user1PositionTicket, await vault.getExitQueueIndex(user1PositionTicket))
      await expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(user1.address, user1PositionTicket, 0, assets)

      tx = await receipt.wait()
      gasUsed = tx.effectiveGasPrice.mul(tx.cumulativeGasUsed)
      expect(await waffle.provider.getBalance(user1.address)).to.be.eq(
        user1BalanceBefore.add(assets).sub(gasUsed)
      )
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(SECURITY_DEPOSIT)
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

    let aliceShares = 0
    let aliceAssets = 0
    let bobShares = 0
    let bobAssets = 0
    let totalAssets = 0
    let totalShares = 0
    let queuedShares = 0
    let unclaimedAssets = 0
    let latestPositionTicket = validatorDeposit
    let vaultLiquidAssets = 0
    let totalReward = 0
    let totalUnlockedMevReward = 0

    const checkVaultState = async () => {
      expect(await vault.getShares(alice.address)).to.be.eq(aliceShares)
      expect(await vault.getShares(bob.address)).to.be.eq(bobShares)
      expect(await vault.convertToAssets(aliceShares)).to.be.eq(aliceAssets)
      expect(await vault.convertToAssets(bobShares)).to.be.eq(bobAssets)
      expect(await vault.totalShares()).to.be.eq(totalShares)
      expect(await waffle.provider.getBalance(sharedMevEscrow.address)).to.be.eq(0)
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(vaultLiquidAssets)
      expect(await vault.totalAssets()).to.be.eq(totalAssets)
      expect(await vault.queuedShares()).to.be.eq(queuedShares)
    }

    // 1. Alice deposits 2000 ETH (mints 2000 shares)
    aliceShares += 2000
    aliceAssets += 2000
    totalAssets += 2000
    vaultLiquidAssets += 2000
    totalShares += 2000
    await vault.connect(alice).deposit(alice.address, referrer, { value: aliceAssets })

    await checkVaultState()

    // 2. Bob deposits 4000 ETH (mints 4000 shares)
    bobShares += 4000
    bobAssets += 4000
    totalAssets += 4000
    vaultLiquidAssets += 4000
    totalShares += 4000
    await vault.connect(bob).deposit(bob.address, referrer, { value: bobAssets })

    await checkVaultState()

    // 3. Vault mutates by +3000 ETH (40% from validators, 60% from priority fees)
    totalAssets += 3000
    totalReward += 3000
    vaultLiquidAssets += 1800
    totalUnlockedMevReward += 1800
    let tree = await updateRewards(keeper, [
      { vault: vault.address, reward: totalReward, unlockedMevReward: totalUnlockedMevReward },
    ])
    let proof = getRewardsRootProof(tree, {
      vault: vault.address,
      reward: totalReward,
      unlockedMevReward: totalUnlockedMevReward,
    })
    await setBalance(sharedMevEscrow.address, BigNumber.from(1800))
    await vault.updateState({
      rewardsRoot: tree.root,
      reward: totalReward,
      unlockedMevReward: totalUnlockedMevReward,
      proof,
    })
    aliceAssets += 1000
    bobAssets += 2000

    await checkVaultState()

    // 4. Alice deposits 2000 ETH (mints 1334 shares)
    aliceShares += 1334
    aliceAssets += 2000
    bobAssets -= 1 // rounding error
    totalAssets += 2000
    vaultLiquidAssets += 2000
    totalShares += 1334

    await vault.connect(alice).deposit(alice.address, referrer, { value: 2000 })
    await checkVaultState()

    // 5. Bob deposits 3000 ETH (mints 2000 shares)
    await vault.connect(bob).deposit(bob.address, referrer, { value: 3000 })
    bobShares += 2001 // rounds up
    bobAssets += 3000
    totalAssets += 3000
    vaultLiquidAssets += 3000
    totalShares += 2001

    await checkVaultState()

    // 6. Vault mutates by +3000 shares
    totalAssets += 3000
    totalReward += 3000
    vaultLiquidAssets += 1800
    totalUnlockedMevReward += 1800
    await setBalance(sharedMevEscrow.address, BigNumber.from(1800))
    tree = await updateRewards(keeper, [
      { vault: vault.address, reward: totalReward, unlockedMevReward: totalUnlockedMevReward },
    ])
    proof = getRewardsRootProof(tree, {
      vault: vault.address,
      reward: totalReward,
      unlockedMevReward: totalUnlockedMevReward,
    })
    await vault.updateState({
      rewardsRoot: tree.root,
      reward: totalReward,
      unlockedMevReward: totalUnlockedMevReward,
      proof,
    })

    aliceAssets += 1071
    bobAssets += 1929

    await checkVaultState()

    // 7. Alice redeems 1333 shares (2427 assets)
    await vault.connect(alice).redeem(1333, alice.address)

    aliceShares -= 1333
    aliceAssets -= 2427
    totalAssets -= 2427
    vaultLiquidAssets -= 2427
    totalShares -= 1333

    await checkVaultState()

    // 8. Bob withdraws 1608 assets (2928 shares)
    await vault.connect(bob).redeem(1608, bob.address)

    bobShares -= 1608
    bobAssets -= 2928
    totalAssets -= 2928
    vaultLiquidAssets -= 2928
    totalShares -= 1608

    await checkVaultState()

    // 9. Most the Vault's assets are staked
    vaultLiquidAssets = 2600
    await setBalance(vault.address, BigNumber.from(2600))

    await checkVaultState()

    await updateRewards(keeper, [
      { vault: vault.address, reward: totalReward, unlockedMevReward: totalUnlockedMevReward },
    ])

    // 10. Alice enters exit queue with 1000 shares
    let alicePositionTicket = await vault
      .connect(alice)
      .callStatic.enterExitQueue(1000, alice.address)
    await expect(vault.connect(alice).enterExitQueue(1000, alice.address))
      .to.emit(vault, 'ExitQueueEntered')
      .withArgs(alice.address, alice.address, alicePositionTicket, 1000)

    aliceShares -= 1000
    aliceAssets -= 1821
    queuedShares += 1000
    expect(alicePositionTicket).to.eq(latestPositionTicket)
    latestPositionTicket = validatorDeposit.add(1000)

    await checkVaultState()

    // 11. Bob enters exit queue with 4393 shares
    let bobPositionTicket = await vault.connect(bob).callStatic.enterExitQueue(4393, bob.address)
    await expect(vault.connect(bob).enterExitQueue(4393, bob.address))
      .to.emit(vault, 'ExitQueueEntered')
      .withArgs(bob.address, bob.address, bobPositionTicket, 4393)

    bobShares -= 4393
    bobAssets -= 8000
    queuedShares += 4393
    expect(bobPositionTicket).to.eq(latestPositionTicket)
    latestPositionTicket = latestPositionTicket.add(4393)

    await checkVaultState()

    // 12. Update exit queue and transfer not staked assets to Bob and Alice
    await expect(
      vault.updateState({
        rewardsRoot: tree.root,
        reward: totalReward,
        unlockedMevReward: totalUnlockedMevReward,
        proof,
      })
    )
      .to.emit(vault, 'CheckpointCreated')
      .withArgs(1427, 2600)

    aliceAssets -= 1 // rounding error
    totalAssets -= 2600
    totalShares -= 1427
    queuedShares -= 1427
    unclaimedAssets += 2600
    await checkVaultState()

    // 13. Vault mutates by +5000 shares
    totalAssets += 5000
    totalReward += 5000
    vaultLiquidAssets += 3000
    totalUnlockedMevReward += 3000

    tree = await updateRewards(keeper, [
      { vault: vault.address, reward: totalReward, unlockedMevReward: totalUnlockedMevReward },
    ])
    await setBalance(sharedMevEscrow.address, BigNumber.from(3000))
    await expect(
      vault.updateState({
        rewardsRoot: tree.root,
        reward: totalReward,
        unlockedMevReward: totalUnlockedMevReward,
        proof: getRewardsRootProof(tree, {
          vault: vault.address,
          reward: totalReward,
          unlockedMevReward: totalUnlockedMevReward,
        }),
      })
    )
      .to.emit(vault, 'CheckpointCreated')
      .withArgs(1060, 3000)

    // update alice assets
    aliceAssets += 1007
    totalShares -= 1060
    totalAssets -= 3000
    queuedShares -= 1060
    unclaimedAssets += 3000
    await checkVaultState()

    // 14. Bob claims exited assets
    let bobCheckpointIdx = await vault.getExitQueueIndex(bobPositionTicket)
    await expect(vault.connect(bob).claimExitedAssets(bobPositionTicket, bobCheckpointIdx))
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(bob.address, bobPositionTicket, bobPositionTicket.add(1487), 3777)

    bobPositionTicket = bobPositionTicket.add(1487)
    vaultLiquidAssets -= 3777
    unclaimedAssets -= 3777
    expect(bobCheckpointIdx).to.eq(1)
    await checkVaultState()

    // 15. Alice claims exited assets
    let aliceCheckpointIdx = await vault.getExitQueueIndex(alicePositionTicket)
    await expect(vault.connect(alice).claimExitedAssets(alicePositionTicket, aliceCheckpointIdx))
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(alice.address, alicePositionTicket, 0, 1822)

    vaultLiquidAssets -= 1822
    unclaimedAssets -= 1822
    expect(aliceCheckpointIdx).to.eq(1)

    await checkVaultState()

    // 16. Alice enters exit queue with 1001 shares
    alicePositionTicket = await vault.connect(alice).callStatic.enterExitQueue(1001, alice.address)
    await expect(vault.connect(alice).enterExitQueue(1001, alice.address))
      .to.emit(vault, 'ExitQueueEntered')
      .withArgs(alice.address, alice.address, alicePositionTicket, 1001)

    expect(alicePositionTicket).to.be.eq(latestPositionTicket)
    queuedShares += 1001
    aliceShares -= 1001
    aliceAssets -= 2829
    await checkVaultState()

    // 17. Withdrawal of all the assets arrives
    await increaseTime(ONE_DAY)
    await setBalance(vault.address, BigNumber.from(totalAssets + unclaimedAssets))
    await updateRewards(keeper, [
      { vault: vault.address, reward: totalReward, unlockedMevReward: totalUnlockedMevReward },
    ])
    await expect(
      vault.updateState({
        rewardsRoot: tree.root,
        reward: totalReward,
        unlockedMevReward: totalUnlockedMevReward,
        proof,
      })
    ).to.emit(vault, 'CheckpointCreated')

    unclaimedAssets += totalAssets
    vaultLiquidAssets = unclaimedAssets
    totalShares = 0
    queuedShares = 0
    totalAssets = 0

    await checkVaultState()

    // 18. Bob claims exited assets
    bobCheckpointIdx = await vault.getExitQueueIndex(bobPositionTicket)
    expect(bobCheckpointIdx).to.eq(3)
    await expect(vault.connect(bob).claimExitedAssets(bobPositionTicket, bobCheckpointIdx))
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(bob.address, bobPositionTicket, 0, 8215)

    vaultLiquidAssets -= 8215
    await checkVaultState()

    // 19. Alice claims exited assets
    aliceCheckpointIdx = await vault.getExitQueueIndex(alicePositionTicket)
    expect(aliceCheckpointIdx).to.eq(3)
    await expect(vault.connect(alice).claimExitedAssets(alicePositionTicket, aliceCheckpointIdx))
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(alice.address, alicePositionTicket, 0, 2829)
    vaultLiquidAssets -= 2829
    await checkVaultState()

    // 20. Check whether state is correct
    aliceShares = 0
    aliceAssets = 0
    bobShares = 0
    bobAssets = 0
    totalAssets = 0
    totalShares = 0
    queuedShares = 0
    vaultLiquidAssets = 2
    await checkVaultState()
  })
})
