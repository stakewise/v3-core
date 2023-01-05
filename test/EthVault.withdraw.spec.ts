import { ethers, waffle } from 'hardhat'
import { BigNumber, Contract, Wallet } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import {
  Keeper,
  EthVault,
  EthVaultMock,
  ExitQueue,
  Oracles,
  IKeeperRewards,
} from '../typechain-types'
import { ThenArg } from '../helpers/types'
import snapshotGasCost from './shared/snapshotGasCost'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { MAX_UINT128, ONE_DAY, PANIC_CODES, ZERO_ADDRESS } from './shared/constants'
import { increaseTime, setBalance } from './shared/utils'
import { collateralizeEthVault, getRewardsRootProof, updateRewardsRoot } from './shared/rewards'
import { registerEthValidator } from './shared/validators'

const createFixtureLoader = waffle.createFixtureLoader
const validatorDeposit = parseEther('32')

describe('EthVault - withdraw', () => {
  const capacity = parseEther('1000')
  const feePercent = 1000
  const name = 'SW ETH Vault'
  const symbol = 'SW-ETH-1'
  const validatorsRoot = '0x059a8487a1ce461e9670c4646ef85164ae8791613866d28c972fb351dc45c606'
  const validatorsIpfsHash = '/ipfs/QmfPnyNojfyqoi9yqS3jMp16GGiTQee4bdCXJC64KqvTgc'
  const metadataIpfsHash = '/ipfs/QmanU2bk9VsJuxhBmvfgXaC44fXpcC8DNHNxPZKMpNXo37'
  const holderShares = parseEther('1')
  const holderAssets = parseEther('1')

  let holder: Wallet, receiver: Wallet, admin: Wallet, dao: Wallet, other: Wallet
  let vault: EthVault, keeper: Keeper, oracles: Oracles, validatorsRegistry: Contract
  let harvestParams: IKeeperRewards.HarvestParamsStruct

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createVault']
  let getSignatures: ThenArg<ReturnType<typeof ethVaultFixture>>['getSignatures']
  let createVaultMock: ThenArg<ReturnType<typeof ethVaultFixture>>['createVaultMock']

  before('create fixture loader', async () => {
    ;[holder, receiver, dao, admin, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([dao])
  })

  beforeEach('deploy fixture', async () => {
    ;({ createVault, createVaultMock, getSignatures, keeper, oracles, validatorsRegistry } =
      await loadFixture(ethVaultFixture))
    vault = await createVault(admin, {
      capacity,
      validatorsRoot,
      feePercent,
      name,
      symbol,
      validatorsIpfsHash,
      metadataIpfsHash,
    })

    // collateralize vault
    const [root, proof] = await collateralizeEthVault(
      vault,
      oracles,
      keeper,
      validatorsRegistry,
      admin,
      getSignatures
    )
    harvestParams = {
      rewardsRoot: root,
      reward: 0,
      proof,
    }

    await vault.connect(holder).deposit(holder.address, { value: holderAssets })
  })

  describe('redeem', () => {
    it('fails with not enough balance', async () => {
      await setBalance(vault.address, BigNumber.from(0))
      await expect(
        vault.connect(holder).redeem(holderShares, receiver.address, holder.address)
      ).to.be.revertedWith('InsufficientAvailableAssets()')
    })

    it('fails for sender other than owner without approval', async () => {
      await expect(
        vault.connect(other).redeem(holderShares, receiver.address, holder.address)
      ).to.be.revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
    })

    it('fails for shares larger than balance', async () => {
      const newBalance = holderShares.add(1)
      await setBalance(vault.address, newBalance)
      await expect(
        vault.connect(holder).redeem(newBalance, receiver.address, holder.address)
      ).to.be.revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
    })

    it('fails for not harvested vault', async () => {
      await vault.updateState(harvestParams)
      await updateRewardsRoot(keeper, oracles, getSignatures, [{ vault: vault.address, reward: 1 }])
      await updateRewardsRoot(keeper, oracles, getSignatures, [{ vault: vault.address, reward: 2 }])
      await expect(
        vault.connect(holder).redeem(holderShares, receiver.address, holder.address)
      ).to.be.revertedWith('NotHarvested()')
    })

    it('reduces allowance for sender other than owner', async () => {
      await vault.connect(holder).approve(other.address, holderShares)
      expect(await vault.allowance(holder.address, other.address)).to.be.eq(holderShares)
      const receipt = await vault
        .connect(other)
        .redeem(holderShares, receiver.address, holder.address)
      expect(await vault.allowance(holder.address, other.address)).to.be.eq(0)

      await snapshotGasCost(receipt)
    })

    it('does not overflow', async () => {
      const vault: EthVaultMock = await createVaultMock(admin, {
        capacity,
        validatorsRoot,
        feePercent,
        name,
        symbol,
        validatorsIpfsHash,
        metadataIpfsHash,
      })
      await vault.connect(holder).deposit(holder.address, { value: holderAssets })

      const receiverBalanceBefore = await waffle.provider.getBalance(receiver.address)

      await setBalance(await vault.address, MAX_UINT128)
      await vault._setTotalAssets(MAX_UINT128)

      await vault.connect(holder).redeem(holderShares, receiver.address, holder.address)
      expect(await vault.totalAssets()).to.be.eq(0)
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore.add(MAX_UINT128)
      )
    })

    it('transfers assets to receiver', async () => {
      const receiverBalanceBefore = await waffle.provider.getBalance(receiver.address)
      const receipt = await vault
        .connect(holder)
        .redeem(holderShares, receiver.address, holder.address)
      await expect(receipt)
        .to.emit(vault, 'Withdraw')
        .withArgs(holder.address, receiver.address, holder.address, holderAssets, holderShares)
      await expect(receipt)
        .to.emit(vault, 'Transfer')
        .withArgs(holder.address, ZERO_ADDRESS, holderShares)

      expect(await vault.totalAssets()).to.be.eq(0)
      expect(await vault.totalSupply()).to.be.eq(0)
      expect(await vault.balanceOf(holder.address)).to.be.eq(0)
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(0)
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore.add(holderAssets)
      )

      await snapshotGasCost(receipt)
    })

    it('does not fail with 0 shares', async () => {
      const receiverBalanceBefore = await waffle.provider.getBalance(receiver.address)
      await vault.connect(holder).redeem(0, receiver.address, holder.address)

      expect(await vault.totalAssets()).to.be.eq(holderAssets)
      expect(await vault.totalSupply()).to.be.eq(holderShares)
      expect(await vault.balanceOf(holder.address)).to.be.eq(holderAssets)
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(holderAssets)
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(receiverBalanceBefore)
    })
  })

  describe('enter exit queue', () => {
    it('fails with 0 shares', async () => {
      await expect(
        vault.connect(holder).enterExitQueue(0, receiver.address, holder.address)
      ).to.be.revertedWith('InvalidSharesAmount()')
    })

    it('fails for not collateralized', async () => {
      const newVault = await createVault(admin, {
        capacity,
        validatorsRoot,
        feePercent,
        name,
        symbol,
        validatorsIpfsHash,
        metadataIpfsHash,
      })
      await newVault.connect(holder).deposit(holder.address, { value: holderAssets })
      await expect(
        newVault.connect(holder).enterExitQueue(holderShares, receiver.address, holder.address)
      ).to.be.revertedWith('NotCollateralized()')
    })

    it('fails for sender other than owner without approval', async () => {
      await expect(
        vault.connect(other).enterExitQueue(holderShares, receiver.address, holder.address)
      ).to.be.revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
    })

    it('fails for shares larger than balance', async () => {
      await expect(
        vault.connect(holder).enterExitQueue(holderShares.add(1), receiver.address, holder.address)
      ).to.be.revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
    })

    it('reduces allowance for sender other than owner', async () => {
      await vault.connect(holder).approve(other.address, holderShares)
      expect(await vault.allowance(holder.address, other.address)).to.be.eq(holderShares)
      const receipt = await vault
        .connect(other)
        .enterExitQueue(holderShares, receiver.address, holder.address)
      expect(await vault.allowance(holder.address, other.address)).to.be.eq(0)

      await snapshotGasCost(receipt)
    })

    it('locks tokens for the time of exit', async () => {
      expect(await vault.queuedShares()).to.be.eq(0)
      expect(await vault.balanceOf(holder.address)).to.be.eq(holderShares)
      expect(await vault.balanceOf(vault.address)).to.be.eq(0)

      const receipt = await vault
        .connect(holder)
        .enterExitQueue(holderShares, receiver.address, holder.address)
      await expect(receipt)
        .to.emit(vault, 'ExitQueueEntered')
        .withArgs(holder.address, receiver.address, holder.address, validatorDeposit, holderShares)
      await expect(receipt)
        .to.emit(vault, 'Transfer')
        .withArgs(holder.address, vault.address, holderShares)

      expect(await vault.queuedShares()).to.be.eq(holderShares)
      expect(await vault.balanceOf(holder.address)).to.be.eq(0)
      expect(await vault.queuedShares()).to.be.eq(holderShares)

      await snapshotGasCost(receipt)
    })
  })

  describe('update exit queue', () => {
    let exitQueue: ExitQueue
    const startCheckpointId = validatorDeposit

    beforeEach(async () => {
      const exitQueueFactory = await ethers.getContractFactory('ExitQueue')
      exitQueue = exitQueueFactory.attach(vault.address) as ExitQueue
      await vault.connect(holder).enterExitQueue(holderShares, receiver.address, holder.address)
    })

    it('skips if it is too early', async () => {
      await vault.updateState(harvestParams)
      await vault.connect(holder).deposit(holder.address, { value: holderAssets })
      await vault.connect(holder).enterExitQueue(holderShares, receiver.address, holder.address)
      await expect(vault.updateState(harvestParams)).to.not.emit(exitQueue, 'CheckpointCreated')
    })

    it('skips with 0 queued shares', async () => {
      await expect(vault.updateState(harvestParams)).to.emit(exitQueue, 'CheckpointCreated')
      expect(await vault.queuedShares()).to.be.eq(0)
      await increaseTime(ONE_DAY)
      await expect(vault.updateState(harvestParams)).to.not.emit(exitQueue, 'CheckpointCreated')
    })

    it('skips with 0 burned assets', async () => {
      const totalAssets = await vault.totalAssets()
      const penalty = totalAssets.sub(totalAssets.mul(2))
      const tree = await updateRewardsRoot(keeper, oracles, getSignatures, [
        { vault: vault.address, reward: penalty },
      ])
      await expect(
        vault.updateState({
          rewardsRoot: tree.root,
          reward: penalty,
          proof: getRewardsRootProof(tree, { vault: vault.address, reward: penalty }),
        })
      ).to.not.emit(exitQueue, 'CheckpointCreated')
    })

    it('for not all the queued shares', async () => {
      const halfHolderAssets = holderAssets.div(2)
      const halfHolderShares = holderShares.div(2)
      await setBalance(vault.address, halfHolderAssets)

      const receipt = await vault.updateState(harvestParams)
      await expect(receipt)
        .to.emit(exitQueue, 'CheckpointCreated')
        .withArgs(startCheckpointId.add(halfHolderShares), halfHolderAssets)
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(halfHolderAssets)
      expect(await vault.queuedShares()).to.be.eq(halfHolderShares)
      expect(await vault.getCheckpointIndex(validatorDeposit)).to.be.eq(1)

      await snapshotGasCost(receipt)
    })

    it('adds checkpoint', async () => {
      const receipt = await vault.updateState(harvestParams)
      await expect(receipt)
        .to.emit(exitQueue, 'CheckpointCreated')
        .withArgs(startCheckpointId.add(holderShares), holderAssets)
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(holderAssets)
      expect(await vault.getCheckpointIndex(0)).to.be.eq(0)
      expect(await vault.totalSupply()).to.be.eq(0)
      expect(await vault.totalAssets()).to.be.eq(0)
      expect(await vault.queuedShares()).to.be.eq(0)

      await snapshotGasCost(receipt)
    })
  })

  it('get checkpoint index works with many checkpoints', async () => {
    const vault: EthVaultMock = await createVaultMock(admin, {
      capacity,
      validatorsRoot,
      feePercent,
      name,
      symbol,
      validatorsIpfsHash,
      metadataIpfsHash,
    })

    // collateralize vault by registering validator
    await vault.connect(holder).deposit(holder.address, { value: validatorDeposit })
    await registerEthValidator(vault, oracles, keeper, validatorsRegistry, admin, getSignatures)

    const exitQueueId = await vault
      .connect(holder)
      .callStatic.enterExitQueue(holderShares, receiver.address, holder.address)
    await vault.connect(holder).enterExitQueue(holderShares, receiver.address, holder.address)
    const exitQueueFactory = await ethers.getContractFactory('ExitQueue')
    const exitQueue = exitQueueFactory.attach(vault.address) as ExitQueue

    // rewards tree updated
    const rewardsTree = await updateRewardsRoot(keeper, oracles, getSignatures, [
      { vault: vault.address, reward: 0 },
    ])
    const proof = getRewardsRootProof(rewardsTree, { vault: vault.address, reward: 0 })

    // create checkpoints every day for 10 years
    for (let i = 1; i <= 3650; i++) {
      await setBalance(vault.address, BigNumber.from(i))
      await increaseTime(ONE_DAY)
      await expect(
        vault.updateState({
          rewardsRoot: rewardsTree.root,
          reward: 0,
          proof,
        })
      ).to.emit(exitQueue, 'CheckpointCreated')
    }
    await snapshotGasCost(await vault.getGasCostOfGetCheckpointIndex(exitQueueId))
  })

  describe('claim exited assets', () => {
    let exitQueue: ExitQueue
    let receiverBalanceBefore: BigNumber
    let exitQueueId

    beforeEach(async () => {
      const exitQueueFactory = await ethers.getContractFactory('ExitQueue')
      exitQueue = exitQueueFactory.attach(vault.address) as ExitQueue
      exitQueueId = await vault
        .connect(holder)
        .callStatic.enterExitQueue(holderShares, receiver.address, holder.address)
      await vault.connect(holder).enterExitQueue(holderShares, receiver.address, holder.address)
      receiverBalanceBefore = await waffle.provider.getBalance(receiver.address)
    })

    it('returns zero with no queued shares', async () => {
      await vault.updateState(harvestParams)
      const checkpointIndex = await vault.getCheckpointIndex(exitQueueId)
      const result = await vault.callStatic.claimExitedAssets(
        other.address,
        exitQueueId,
        checkpointIndex
      )
      expect(result.newExitQueueId).to.be.eq(exitQueueId)
      expect(result.claimedAssets).to.be.eq(0)
      await expect(
        vault.connect(other).claimExitedAssets(other.address, exitQueueId, checkpointIndex)
      ).to.not.emit(vault, 'ExitedAssetsClaimed')
    })

    it('returns -1 for unknown checkpoint index', async () => {
      expect(await vault.getCheckpointIndex(validatorDeposit)).to.be.eq(-1)
    })

    it('returns 0 with checkpoint index larger than checkpoints array', async () => {
      const result = await vault.callStatic.claimExitedAssets(receiver.address, exitQueueId, 1)
      expect(result.newExitQueueId).to.be.eq(validatorDeposit)
      expect(result.claimedAssets).to.be.eq(0)
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(receiverBalanceBefore)
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(holderAssets)
    })

    it('fails with invalid checkpoint index', async () => {
      await vault.updateState(harvestParams)
      const checkpointIndex = await vault.getCheckpointIndex(exitQueueId)

      await vault.connect(holder).deposit(holder.address, { value: holderAssets.mul(2) })
      const exitQueueId2 = await vault
        .connect(holder)
        .callStatic.enterExitQueue(holderShares, receiver.address, holder.address)
      await vault.connect(holder).enterExitQueue(holderShares, receiver.address, holder.address)
      // checkpointIndex is lower than exitQueueId
      await expect(
        vault.connect(holder).claimExitedAssets(receiver.address, exitQueueId2, checkpointIndex)
      ).to.be.revertedWith('InvalidCheckpointIndex()')
      await increaseTime(ONE_DAY)
      await vault.updateState(harvestParams)

      const exitQueueId3 = await vault
        .connect(holder)
        .callStatic.enterExitQueue(holderShares, receiver.address, holder.address)
      await vault.connect(holder).enterExitQueue(holderShares, receiver.address, holder.address)
      await increaseTime(ONE_DAY)
      await vault.updateState(harvestParams)
      const checkpointIndexThree = await vault.getCheckpointIndex(exitQueueId3)
      // checkpointIndex is higher than exitQueueId
      await expect(
        vault.connect(holder).claimExitedAssets(receiver.address, exitQueueId, checkpointIndexThree)
      ).to.be.revertedWith('InvalidCheckpointIndex()')
    })

    it('for single user in single checkpoint', async () => {
      await vault.updateState(harvestParams)
      const checkpointIndex = await vault.getCheckpointIndex(exitQueueId)

      const receipt = await vault
        .connect(holder)
        .claimExitedAssets(receiver.address, exitQueueId, checkpointIndex)
      await expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(holder.address, receiver.address, exitQueueId, 0, holderAssets)
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore.add(holderAssets)
      )
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(0)

      await snapshotGasCost(receipt)
    })

    it('for single user in multiple checkpoints in single transaction', async () => {
      const halfHolderAssets = holderAssets.div(2)
      const halfHolderShares = holderShares.div(2)

      // create two checkpoints
      await setBalance(vault.address, halfHolderAssets)
      await expect(vault.updateState(harvestParams))
        .to.emit(exitQueue, 'CheckpointCreated')
        .withArgs(validatorDeposit.add(halfHolderShares), halfHolderAssets)
      const checkpointIndex = await vault.getCheckpointIndex(exitQueueId)

      await increaseTime(ONE_DAY)
      await setBalance(vault.address, holderAssets)
      await expect(vault.updateState(harvestParams))
        .to.emit(exitQueue, 'CheckpointCreated')
        .withArgs(validatorDeposit.add(holderShares), halfHolderAssets)

      const receipt = await vault
        .connect(holder)
        .claimExitedAssets(receiver.address, exitQueueId, checkpointIndex)

      await expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(holder.address, receiver.address, exitQueueId, 0, holderAssets)
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore.add(holderAssets)
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
        .to.emit(exitQueue, 'CheckpointCreated')
        .withArgs(validatorDeposit.add(halfHolderShares), halfHolderAssets)
      const checkpointIndex = await vault.getCheckpointIndex(exitQueueId)
      let receipt = await vault
        .connect(holder)
        .claimExitedAssets(receiver.address, exitQueueId, checkpointIndex)

      const newExitQueueId = validatorDeposit.add(halfHolderShares)
      await expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(holder.address, receiver.address, exitQueueId, newExitQueueId, halfHolderAssets)
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore.add(halfHolderAssets)
      )

      await snapshotGasCost(receipt)

      // create second checkpoint
      await increaseTime(ONE_DAY)
      await setBalance(vault.address, halfHolderAssets)
      await expect(vault.updateState(harvestParams))
        .to.emit(exitQueue, 'CheckpointCreated')
        .withArgs(validatorDeposit.add(holderShares), halfHolderAssets)

      const newCheckpointIndex = await vault.getCheckpointIndex(newExitQueueId)
      receipt = await vault
        .connect(holder)
        .claimExitedAssets(receiver.address, newExitQueueId, newCheckpointIndex)
      await expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(holder.address, receiver.address, newExitQueueId, 0, halfHolderAssets)
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore.add(holderAssets)
      )
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(0)

      await snapshotGasCost(receipt)
    })

    it('for multiple users in single checkpoint', async () => {
      // harvests the previous queued position
      await vault.updateState(harvestParams)
      const checkpointIndex = await vault.getCheckpointIndex(exitQueueId)
      await vault.connect(holder).claimExitedAssets(receiver.address, exitQueueId, checkpointIndex)

      const shares = holderShares
      const assets = holderAssets
      const user1 = holder
      const user2 = receiver

      await vault.connect(user1).deposit(user1.address, { value: assets })
      await vault.connect(user2).deposit(user2.address, { value: assets })

      const user1ExitQueueId = await vault
        .connect(user1)
        .callStatic.enterExitQueue(shares, user1.address, user1.address)
      await vault.connect(user1).enterExitQueue(shares, user1.address, user1.address)
      const user1BalanceBefore = await waffle.provider.getBalance(user1.address)

      const user2ExitQueueId = await vault
        .connect(user2)
        .callStatic.enterExitQueue(shares, user2.address, user2.address)
      await vault.connect(user2).enterExitQueue(shares, user2.address, user2.address)
      const user2BalanceBefore = await waffle.provider.getBalance(user2.address)

      await increaseTime(ONE_DAY)
      await expect(vault.connect(other).updateState(harvestParams))
        .to.emit(exitQueue, 'CheckpointCreated')
        .withArgs(user2ExitQueueId.add(assets), assets.mul(2))

      let receipt = await vault
        .connect(other)
        .claimExitedAssets(
          user2.address,
          user2ExitQueueId,
          await vault.getCheckpointIndex(user2ExitQueueId)
        )
      await expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(other.address, user2.address, user2ExitQueueId, 0, assets)
      expect(await waffle.provider.getBalance(user2.address)).to.be.eq(
        user2BalanceBefore.add(assets)
      )

      receipt = await vault
        .connect(other)
        .claimExitedAssets(
          user1.address,
          user1ExitQueueId,
          await vault.getCheckpointIndex(user1ExitQueueId)
        )
      await expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(other.address, user1.address, user1ExitQueueId, 0, assets)
      expect(await waffle.provider.getBalance(user1.address)).to.be.eq(
        user1BalanceBefore.add(assets)
      )
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(0)
    })
  })

  /// Scenario inspired by solmate ERC4626 tests:
  /// https://github.com/transmissions11/solmate/blob/main/src/test/ERC4626.t.sol
  it('multiple deposits and withdrawals', async () => {
    const vault = await createVaultMock(admin, {
      capacity,
      validatorsRoot,
      feePercent: 0,
      name,
      symbol,
      validatorsIpfsHash,
      metadataIpfsHash,
    })
    const mevEscrow = await vault.mevEscrow()
    const exitQueueFactory = await ethers.getContractFactory('ExitQueue')
    const exitQueue = exitQueueFactory.attach(vault.address)
    const alice = holder
    const bob = other

    // collateralize vault by registering validator
    await collateralizeEthVault(vault, oracles, keeper, validatorsRegistry, admin, getSignatures)

    let aliceShares = 0
    let aliceAssets = 0
    let bobShares = 0
    let bobAssets = 0
    let totalStakedAssets = 0
    let totalSupply = 0
    let queuedShares = 0
    let unclaimedAssets = 0
    let latestExitQueueId = validatorDeposit
    let vaultAssets = 0
    let validatorsReward = 0

    const checkVaultState = async () => {
      expect(await vault.balanceOf(alice.address)).to.be.eq(aliceShares)
      expect(await vault.balanceOf(bob.address)).to.be.eq(bobShares)
      expect(await vault.convertToAssets(aliceShares)).to.be.eq(aliceAssets)
      expect(await vault.convertToAssets(bobShares)).to.be.eq(bobAssets)
      expect(await vault.totalSupply()).to.be.eq(totalSupply)
      expect(await waffle.provider.getBalance(mevEscrow)).to.be.eq(0)
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(vaultAssets)
      expect(await vault.totalAssets()).to.be.eq(totalStakedAssets)
      expect(await vault.queuedShares()).to.be.eq(queuedShares)
      expect(await vault.unclaimedAssets()).to.be.eq(unclaimedAssets)
    }

    // 1. Alice deposits 2000 ETH (mints 2000 shares)
    aliceShares += 2000
    aliceAssets += 2000
    totalStakedAssets += 2000
    vaultAssets += 2000
    totalSupply += 2000
    await expect(vault.connect(alice).deposit(alice.address, { value: aliceAssets }))
      .to.emit(vault, 'Transfer')
      .withArgs(ZERO_ADDRESS, alice.address, aliceShares)

    await checkVaultState()

    // 2. Bob deposits 4000 ETH (mints 4000 shares)
    bobShares += 4000
    bobAssets += 4000
    totalStakedAssets += 4000
    vaultAssets += 4000
    totalSupply += 4000
    await expect(vault.connect(bob).deposit(bob.address, { value: bobAssets }))
      .to.emit(vault, 'Transfer')
      .withArgs(ZERO_ADDRESS, bob.address, bobShares)

    await checkVaultState()

    // 3. Vault mutates by +3000 ETH (40% from validators, 60% from priority fees)
    vaultAssets += 1800
    totalStakedAssets += 3000
    validatorsReward += 1200
    let tree = await updateRewardsRoot(keeper, oracles, getSignatures, [
      { vault: vault.address, reward: validatorsReward },
    ])
    let proof = getRewardsRootProof(tree, { vault: vault.address, reward: validatorsReward })
    await setBalance(mevEscrow, BigNumber.from(1800))
    await vault.updateState({
      rewardsRoot: tree.root,
      reward: validatorsReward,
      proof,
    })
    aliceAssets += 1000
    bobAssets += 2000

    await checkVaultState()

    // 4. Alice deposits 2000 ETH (mints 1333 shares)
    aliceShares += 1333
    aliceAssets += 1999 // rounds down
    totalStakedAssets += 2000
    vaultAssets += 2000
    totalSupply += 1333

    await expect(vault.connect(alice).deposit(alice.address, { value: 2000 }))
      .to.emit(vault, 'Transfer')
      .withArgs(ZERO_ADDRESS, alice.address, 1333)

    await checkVaultState()

    // 5. Bob deposits 3000 ETH (mints 1999 shares)
    await expect(vault.connect(bob).deposit(bob.address, { value: 3000 }))
      .to.emit(vault, 'Transfer')
      .withArgs(ZERO_ADDRESS, bob.address, 1999)
    aliceAssets += 1 // rounds up
    bobShares += 1999 // rounds down
    bobAssets += 2999 // rounds down
    totalStakedAssets += 3000
    vaultAssets += 3000
    totalSupply += 1999

    await checkVaultState()

    // 6. Vault mutates by +3000 tokens
    vaultAssets += 1800
    totalStakedAssets += 3000
    validatorsReward += 1200
    await setBalance(mevEscrow, BigNumber.from(1800))
    tree = await updateRewardsRoot(keeper, oracles, getSignatures, [
      { vault: vault.address, reward: validatorsReward },
    ])
    proof = getRewardsRootProof(tree, { vault: vault.address, reward: validatorsReward })
    await vault.updateState({
      rewardsRoot: tree.root,
      reward: validatorsReward,
      proof,
    })

    aliceAssets += 1071
    bobAssets += 1929

    await checkVaultState()

    // 7. Alice redeems 1333 shares (2428 assets)
    await expect(vault.connect(alice).redeem(1333, alice.address, alice.address))
      .to.emit(vault, 'Transfer')
      .withArgs(alice.address, ZERO_ADDRESS, 1333)

    aliceShares -= 1333
    aliceAssets -= 2428
    totalStakedAssets -= 2428
    vaultAssets -= 2428
    totalSupply -= 1333

    await checkVaultState()

    // 8. Bob redeems 1608 shares (2929 assets)
    const receipt = await vault.connect(bob).redeem(1608, bob.address, bob.address)
    await expect(receipt).to.emit(vault, 'Transfer').withArgs(bob.address, ZERO_ADDRESS, 1608)

    bobShares -= 1608
    bobAssets -= 2929
    totalStakedAssets -= 2929
    vaultAssets -= 2929
    totalSupply -= 1608

    await checkVaultState()

    // 9. Most the Vault's assets are staked
    vaultAssets = 2600
    await setBalance(vault.address, BigNumber.from(2600))

    await checkVaultState()

    // 10. Alice enters exit queue with 1000 shares
    let aliceExitQueueId = await vault
      .connect(alice)
      .callStatic.enterExitQueue(1000, alice.address, alice.address)
    await expect(vault.connect(alice).enterExitQueue(1000, alice.address, alice.address))
      .to.emit(vault, 'ExitQueueEntered')
      .withArgs(alice.address, alice.address, alice.address, aliceExitQueueId, 1000)

    aliceShares -= 1000
    aliceAssets -= 1822
    queuedShares += 1000
    expect(aliceExitQueueId).to.eq(latestExitQueueId)
    latestExitQueueId = validatorDeposit.add(1000)

    await checkVaultState()

    // 11. Bob enters exit queue with 4391 shares
    let bobExitQueueId = await vault
      .connect(bob)
      .callStatic.enterExitQueue(4391, bob.address, bob.address)
    await expect(vault.connect(bob).enterExitQueue(4391, bob.address, bob.address))
      .to.emit(vault, 'ExitQueueEntered')
      .withArgs(bob.address, bob.address, bob.address, bobExitQueueId, 4391)

    bobShares -= 4391
    bobAssets -= 7999
    queuedShares += 4391
    expect(bobExitQueueId).to.eq(latestExitQueueId)
    latestExitQueueId = latestExitQueueId.add(4391)

    await checkVaultState()

    // 12. Update exit queue and transfer not staked assets to Bob and Alice
    await expect(
      vault.updateState({
        rewardsRoot: tree.root,
        reward: validatorsReward,
        proof,
      })
    )
      .to.emit(exitQueue, 'CheckpointCreated')
      .withArgs(validatorDeposit.add(1427), 2600)

    totalStakedAssets -= 2600
    totalSupply -= 1427
    queuedShares -= 1427
    unclaimedAssets += 2600

    await checkVaultState()

    // 13. Vault mutates by +5000 tokens
    vaultAssets += 3000
    totalStakedAssets += 5000
    validatorsReward += 2000
    aliceAssets += 1007
    tree = await updateRewardsRoot(keeper, oracles, getSignatures, [
      { vault: vault.address, reward: validatorsReward },
    ])
    await setBalance(mevEscrow, BigNumber.from(3000))
    await vault.updateState({
      rewardsRoot: tree.root,
      reward: validatorsReward,
      proof: getRewardsRootProof(tree, { vault: vault.address, reward: validatorsReward }),
    })

    await checkVaultState()

    // 14. Bob claims exited assets
    let bobCheckpointIdx = await vault.getCheckpointIndex(bobExitQueueId)
    await expect(
      vault.connect(bob).claimExitedAssets(bob.address, bobExitQueueId, bobCheckpointIdx)
    )
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(bob.address, bob.address, bobExitQueueId, validatorDeposit.add(1427), 777)

    bobExitQueueId = validatorDeposit.add(1427)
    vaultAssets -= 777
    unclaimedAssets -= 777
    expect(bobCheckpointIdx).to.eq(1)
    await checkVaultState()

    // 15. Alice claims exited assets
    let aliceCheckpointIdx = await vault.getCheckpointIndex(aliceExitQueueId)
    await expect(
      vault.connect(alice).claimExitedAssets(alice.address, aliceExitQueueId, aliceCheckpointIdx)
    )
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(alice.address, alice.address, aliceExitQueueId, 0, 1822)

    vaultAssets -= 1822
    unclaimedAssets -= 1822
    expect(aliceCheckpointIdx).to.eq(1)

    await checkVaultState()

    // 16. Update exit queue and transfer assets to Bob
    await increaseTime(ONE_DAY)
    await expect(
      vault.updateState({
        rewardsRoot: tree.root,
        reward: validatorsReward,
        proof,
      })
    )
      .to.emit(exitQueue, 'CheckpointCreated')
      .withArgs(validatorDeposit.add(2487), 3000)

    totalStakedAssets -= 3000
    totalSupply -= 1060
    queuedShares -= 1060
    unclaimedAssets += 3000
    await checkVaultState()

    // 17. Alice enters exit queue with 1000 shares
    aliceExitQueueId = await vault
      .connect(alice)
      .callStatic.enterExitQueue(1000, alice.address, alice.address)
    await expect(vault.connect(alice).enterExitQueue(1000, alice.address, alice.address))
      .to.emit(vault, 'ExitQueueEntered')
      .withArgs(alice.address, alice.address, alice.address, aliceExitQueueId, 1000)

    expect(aliceExitQueueId).to.be.eq(latestExitQueueId)
    queuedShares += 1000
    aliceShares -= 1000
    aliceAssets -= 2828
    await checkVaultState()

    // 18. Withdrawal of 11050 ETH arrives
    await increaseTime(ONE_DAY)
    await setBalance(vault.address, BigNumber.from(11050 + vaultAssets))
    await expect(
      vault.updateState({
        rewardsRoot: tree.root,
        reward: validatorsReward,
        proof,
      })
    )
      .to.emit(exitQueue, 'CheckpointCreated')
      .withArgs(validatorDeposit.add(6391), 11043)

    vaultAssets += 11050
    totalSupply -= 3904
    queuedShares -= 3904
    totalStakedAssets -= 11043
    unclaimedAssets += 11043

    await checkVaultState()

    // 19. Bob claims exited assets
    bobCheckpointIdx = await vault.getCheckpointIndex(bobExitQueueId)
    expect(bobCheckpointIdx).to.eq(2)
    await expect(
      vault.connect(bob).claimExitedAssets(bob.address, bobExitQueueId, bobCheckpointIdx)
    )
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(bob.address, bob.address, bobExitQueueId, 0, 11214)

    unclaimedAssets -= 11214
    vaultAssets -= 11214
    await checkVaultState()

    // 20. Alice claims exited assets
    aliceCheckpointIdx = await vault.getCheckpointIndex(aliceExitQueueId)
    expect(aliceCheckpointIdx).to.eq(3)
    await expect(
      vault.connect(alice).claimExitedAssets(alice.address, aliceExitQueueId, aliceCheckpointIdx)
    )
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(alice.address, alice.address, aliceExitQueueId, 0, 2828)

    unclaimedAssets -= 2828
    vaultAssets -= 2828
    await checkVaultState()

    // 21. Check whether state is correct
    aliceShares = 0
    aliceAssets = 0
    bobShares = 0
    bobAssets = 0
    totalStakedAssets = 0
    totalSupply = 0
    queuedShares = 0
    unclaimedAssets = 2
    vaultAssets = 9
    await checkVaultState()
  })
})
