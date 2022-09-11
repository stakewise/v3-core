import { ethers, waffle } from 'hardhat'
import { BigNumber, Wallet } from 'ethers'
import { ExitQueue } from '../typechain-types'
import { EthVault, EthVaultMock } from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { vaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { ONE_DAY, MAX_UINT128, PANIC_CODES, ZERO_ADDRESS } from './shared/constants'
import { increaseTime, setBalance } from './shared/utils'

const createFixtureLoader = waffle.createFixtureLoader
const parseEther = ethers.utils.parseEther

type ThenArg<T> = T extends PromiseLike<infer U> ? U : T

describe('EthVault - withdraw', () => {
  let holder: Wallet, receiver: Wallet, other: Wallet
  let vault: EthVault
  let feesEscrow: string
  const holderShares = parseEther('1')
  const holderAssets = parseEther('1')

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createEthVault: ThenArg<ReturnType<typeof vaultFixture>>['createEthVault']
  let createEthVaultMock: ThenArg<ReturnType<typeof vaultFixture>>['createEthVaultMock']

  before('create fixture loader', async () => {
    ;[holder, receiver, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([holder, receiver, other])
  })

  beforeEach('deploy fixture', async () => {
    ;({ createEthVault, createEthVaultMock } = await loadFixture(vaultFixture))
    vault = await createEthVault()
    feesEscrow = await vault.feesEscrow()
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

    it('reduces allowance for sender other than owner', async () => {
      await vault.connect(holder).approve(other.address, holderShares)
      expect(await vault.allowance(holder.address, other.address)).to.be.eq(holderShares)
      const receipt = await vault
        .connect(other)
        .redeem(holderShares, receiver.address, holder.address)
      await snapshotGasCost(receipt)
      expect(await vault.allowance(holder.address, other.address)).to.be.eq(0)
    })

    it('claims fees with not enough vault assets', async () => {
      const escrowBalance = holderAssets
      await setBalance(vault.address, BigNumber.from(0))
      await setBalance(feesEscrow, escrowBalance)

      const sharesToRedeem = holderShares.div(2)
      const receipt = await vault
        .connect(holder)
        .redeem(sharesToRedeem, receiver.address, holder.address)
      await snapshotGasCost(receipt)

      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(0)
      expect(await vault.totalAssets()).to.be.eq(holderShares)
      expect(await vault.totalSupply()).to.be.eq(sharesToRedeem)
      expect(await vault.balanceOf(holder.address)).to.be.eq(sharesToRedeem)
    })

    it('does not overflow', async () => {
      const vault: EthVaultMock = await createEthVaultMock(1)
      await vault.connect(holder).deposit(holder.address, { value: holderAssets })

      const feesEscrow = await vault.feesEscrow()
      const halfTotalAssets = MAX_UINT128.div(2)
      const halfHolderShares = holderShares.div(2)
      const receiverBalanceBefore = await waffle.provider.getBalance(receiver.address)

      await setBalance(await vault.address, BigNumber.from(0))
      await setBalance(feesEscrow, halfTotalAssets)
      await vault._setTotalStakedAssets(halfTotalAssets)

      await vault.connect(holder).redeem(halfHolderShares, receiver.address, holder.address)
      expect(await waffle.provider.getBalance(feesEscrow)).to.be.eq(0)
      expect(await vault.totalAssets()).to.be.eq(halfTotalAssets)
      expect(await vault.convertToAssets(await vault.balanceOf(holder.address))).to.be.eq(
        halfTotalAssets
      )
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore.add(halfTotalAssets)
      )
    })

    it('transfers assets to receiver', async () => {
      const receiverBalanceBefore = await waffle.provider.getBalance(receiver.address)
      const receipt = await vault
        .connect(holder)
        .redeem(holderShares, receiver.address, holder.address)
      await snapshotGasCost(receipt)
      expect(receipt)
        .to.emit(vault, 'Withdraw')
        .withArgs(holder.address, receiver.address, holder.address, holderAssets, holderShares)
      expect(receipt)
        .to.emit(vault, 'Transfer')
        .withArgs(holder.address, ZERO_ADDRESS, holderShares)

      expect(await vault.totalAssets()).to.be.eq(0)
      expect(await vault.totalSupply()).to.be.eq(0)
      expect(await vault.balanceOf(holder.address)).to.be.eq(0)
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(0)
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore.add(holderAssets)
      )
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
      await snapshotGasCost(receipt)
      expect(await vault.allowance(holder.address, other.address)).to.be.eq(0)
    })

    it('locks tokens for the time of exit', async () => {
      expect(await vault.availableAssets()).to.be.eq(holderAssets)
      expect(await vault.balanceOf(holder.address)).to.be.eq(holderShares)
      expect(await vault.balanceOf(vault.address)).to.be.eq(0)

      const receipt = await vault
        .connect(holder)
        .enterExitQueue(holderShares, receiver.address, holder.address)
      await snapshotGasCost(receipt)
      expect(receipt)
        .to.emit(vault, 'ExitQueueEnter')
        .withArgs(holder.address, receiver.address, holder.address, 0, holderShares)
      expect(receipt)
        .to.emit(vault, 'Transfer')
        .withArgs(holder.address, vault.address, holderShares)

      expect(await vault.availableAssets()).to.be.eq(0)
      expect(await vault.balanceOf(holder.address)).to.be.eq(0)
      expect(await vault.queuedShares()).to.be.eq(holderShares)
    })
  })

  describe('update exit queue', () => {
    let exitQueue: ExitQueue

    beforeEach(async () => {
      const exitQueueFactory = await ethers.getContractFactory('ExitQueue')
      exitQueue = exitQueueFactory.attach(vault.address) as ExitQueue
      await vault.connect(holder).enterExitQueue(holderShares, receiver.address, holder.address)
    })

    it('fails if it is too early', async () => {
      await vault.connect(other).updateExitQueue()
      await expect(vault.connect(other).updateExitQueue()).to.be.revertedWith(
        'EarlyExitQueueUpdate()'
      )
    })

    it('skips with 0 queued shares', async () => {
      await expect(vault.connect(other).updateExitQueue()).to.emit(exitQueue, 'CheckpointCreated')
      await increaseTime(ONE_DAY)
      await expect(vault.connect(other).updateExitQueue()).to.not.emit(
        exitQueue,
        'CheckpointCreated'
      )
    })

    it("claims fees with required assets larger than vault's balance", async () => {
      await setBalance(feesEscrow, holderAssets)
      const receipt = await vault.connect(other).updateExitQueue()

      expect(receipt)
        .to.emit(exitQueue, 'CheckpointCreated')
        .withArgs(holderShares, holderAssets.mul(2))
      await snapshotGasCost(receipt)
      expect(await waffle.provider.getBalance(feesEscrow)).to.be.eq(0)
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(holderAssets.mul(2))
      expect(await vault.queuedShares()).to.be.eq(0)
      expect(await vault.getCheckpointIndex(0)).to.be.eq(0)
    })

    it('for not all the queued shares', async () => {
      const halfHolderAssets = holderAssets.div(2)
      const halfHolderShares = holderShares.div(2)
      await setBalance(vault.address, halfHolderAssets)

      const receipt = await vault.connect(other).updateExitQueue()
      expect(receipt)
        .to.emit(exitQueue, 'CheckpointCreated')
        .withArgs(halfHolderShares, halfHolderAssets)
      await snapshotGasCost(receipt)
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(halfHolderAssets)
      expect(await vault.queuedShares()).to.be.eq(halfHolderShares)
      expect(await vault.getCheckpointIndex(0)).to.be.eq(0)
    })

    it('adds checkpoint', async () => {
      const receipt = await vault.connect(other).updateExitQueue()
      expect(receipt).to.emit(exitQueue, 'CheckpointCreated').withArgs(holderShares, holderAssets)
      await snapshotGasCost(receipt)
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(holderAssets)
      expect(await vault.getCheckpointIndex(0)).to.be.eq(0)
      expect(await vault.availableAssets()).to.be.eq(0)
      expect(await vault.totalSupply()).to.be.eq(0)
      expect(await vault.totalAssets()).to.be.eq(0)
      expect(await vault.queuedShares()).to.be.eq(0)
    })
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

    it('fails with no queued shares', async () => {
      await expect(
        vault.connect(other).claimExitedAssets(other.address, exitQueueId, 1)
      ).to.be.revertedWith('NoExitRequestingShares()')
    })

    it('returns -1 for unknown checkpoint index', async () => {
      expect(await vault.getCheckpointIndex(0)).to.be.eq(-1)
    })

    it('returns 0 with checkpoint index larger than checkpoints array', async () => {
      const result = await vault.callStatic.claimExitedAssets(receiver.address, exitQueueId, 1)
      expect(result.newExitQueueId).to.be.eq(0)
      expect(result.claimedAssets).to.be.eq(0)
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(receiverBalanceBefore)
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(holderAssets)
    })

    it('fails with invalid checkpoint index', async () => {
      await vault.updateExitQueue()
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
      await vault.updateExitQueue()

      const exitQueueId3 = await vault
        .connect(holder)
        .callStatic.enterExitQueue(holderShares, receiver.address, holder.address)
      await vault.connect(holder).enterExitQueue(holderShares, receiver.address, holder.address)
      await increaseTime(ONE_DAY)
      await vault.updateExitQueue()
      const checkpointIndexThree = await vault.getCheckpointIndex(exitQueueId3)
      // checkpointIndex is higher than exitQueueId
      await expect(
        vault.connect(holder).claimExitedAssets(receiver.address, exitQueueId, checkpointIndexThree)
      ).to.be.revertedWith('InvalidCheckpointIndex()')
    })

    it('for single user in single checkpoint', async () => {
      await vault.updateExitQueue()
      const checkpointIndex = await vault.getCheckpointIndex(exitQueueId)

      const receipt = await vault
        .connect(holder)
        .claimExitedAssets(receiver.address, exitQueueId, checkpointIndex)
      await snapshotGasCost(receipt)
      expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaim')
        .withArgs(holder.address, receiver.address, exitQueueId, 0, holderAssets)
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore.add(holderAssets)
      )
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(0)
    })

    it('for single user in multiple checkpoints in single transaction', async () => {
      const halfHolderAssets = holderAssets.div(2)
      const halfHolderShares = holderShares.div(2)

      // create two checkpoints
      await setBalance(vault.address, halfHolderAssets)
      await expect(await vault.updateExitQueue())
        .to.emit(exitQueue, 'CheckpointCreated')
        .withArgs(halfHolderShares, halfHolderAssets)
      const checkpointIndex = await vault.getCheckpointIndex(exitQueueId)

      await increaseTime(ONE_DAY)
      await setBalance(vault.address, holderAssets)
      await expect(await vault.updateExitQueue())
        .to.emit(exitQueue, 'CheckpointCreated')
        .withArgs(holderShares, halfHolderAssets)

      const receipt = await vault
        .connect(holder)
        .claimExitedAssets(receiver.address, exitQueueId, checkpointIndex)
      await snapshotGasCost(receipt)

      expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaim')
        .withArgs(holder.address, receiver.address, exitQueueId, 0, holderAssets)
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore.add(holderAssets)
      )
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(0)
    })

    it('for single user in multiple checkpoints in multiple transactions', async () => {
      const halfHolderAssets = holderAssets.div(2)
      const halfHolderShares = holderShares.div(2)

      // create first checkpoint
      await setBalance(vault.address, halfHolderAssets)
      await expect(vault.updateExitQueue())
        .to.emit(exitQueue, 'CheckpointCreated')
        .withArgs(halfHolderShares, halfHolderAssets)
      const checkpointIndex = await vault.getCheckpointIndex(exitQueueId)
      const receipt = await vault
        .connect(holder)
        .claimExitedAssets(receiver.address, exitQueueId, checkpointIndex)
      await snapshotGasCost(receipt)

      const newExitQueueId = halfHolderShares
      expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaim')
        .withArgs(holder.address, receiver.address, exitQueueId, newExitQueueId, halfHolderAssets)
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore.add(halfHolderAssets)
      )

      // create second checkpoint
      await increaseTime(ONE_DAY)
      await setBalance(vault.address, halfHolderAssets)
      await expect(await vault.updateExitQueue())
        .to.emit(exitQueue, 'CheckpointCreated')
        .withArgs(holderShares, halfHolderAssets)

      const newCheckpointIndex = await vault.getCheckpointIndex(newExitQueueId)
      await expect(
        vault
          .connect(holder)
          .claimExitedAssets(receiver.address, newExitQueueId, newCheckpointIndex)
      )
        .to.emit(vault, 'ExitedAssetsClaim')
        .withArgs(holder.address, receiver.address, newExitQueueId, 0, halfHolderAssets)
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore.add(holderAssets)
      )
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(0)
    })

    it('for multiple users in single checkpoint', async () => {
      await vault.connect(other).deposit(other.address, { value: holderAssets })
      await vault.connect(other).enterExitQueue(holderShares, other.address, other.address)
      const otherBalanceBefore = await waffle.provider.getBalance(other.address)

      await expect(await vault.updateExitQueue())
        .to.emit(exitQueue, 'CheckpointCreated')
        .withArgs(holderShares.mul(2), holderAssets.mul(2))
      const checkpointIndex = await vault.getCheckpointIndex(exitQueueId)

      let receipt = await vault
        .connect(holder)
        .claimExitedAssets(receiver.address, exitQueueId, checkpointIndex)
      expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaim')
        .withArgs(holder.address, receiver.address, exitQueueId, 0, holderAssets)
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore.add(holderAssets)
      )

      const otherExitQueueId = holderShares.add(exitQueueId)
      receipt = await vault
        .connect(holder)
        .claimExitedAssets(other.address, otherExitQueueId, checkpointIndex)
      expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaim')
        .withArgs(holder.address, other.address, otherExitQueueId, 0, holderAssets)
      expect(await waffle.provider.getBalance(other.address)).to.be.eq(
        otherBalanceBefore.add(holderAssets)
      )

      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(0)
    })
  })

  /// Scenario inspired by solmate ERC4626 tests:
  /// https://github.com/transmissions11/solmate/blob/main/src/test/ERC4626.t.sol
  it('multiple deposits and withdrawals', async () => {
    const vault = await createEthVaultMock(1)
    const feesEscrow = await vault.feesEscrow()
    const exitQueueFactory = await ethers.getContractFactory('ExitQueue')
    const exitQueue = exitQueueFactory.attach(vault.address)
    const alice = holder
    const bob = other

    let aliceShares = 0
    let aliceAssets = 0
    let bobShares = 0
    let bobAssets = 0
    let feesEscrowAssets = 0
    let totalStakedAssets = 0
    let totalSupply = 0
    let queuedShares = 0
    let unclaimedAssets = 0
    let latestExitQueueId = 0
    let vaultAssets = 0

    const checkVaultState = async () => {
      expect(await vault.balanceOf(alice.address)).to.be.eq(aliceShares)
      expect(await vault.balanceOf(bob.address)).to.be.eq(bobShares)
      expect(await vault.convertToAssets(aliceShares)).to.be.eq(aliceAssets)
      expect(await vault.convertToAssets(bobShares)).to.be.eq(bobAssets)
      expect(await vault.totalSupply()).to.be.eq(totalSupply)
      expect(await waffle.provider.getBalance(feesEscrow)).to.be.eq(feesEscrowAssets)
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(vaultAssets)
      expect(await vault.totalAssets()).to.be.eq(totalStakedAssets + feesEscrowAssets)
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
    feesEscrowAssets += 1800
    totalStakedAssets += 1200
    await setBalance(feesEscrow, BigNumber.from(feesEscrowAssets))
    await vault.connect(receiver)._setTotalStakedAssets(totalStakedAssets)
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
    feesEscrowAssets += 1800
    totalStakedAssets += 1200
    await setBalance(feesEscrow, BigNumber.from(feesEscrowAssets))
    await vault.connect(receiver)._setTotalStakedAssets(totalStakedAssets)

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
    expect(receipt).to.emit(vault, 'Transfer').withArgs(bob.address, ZERO_ADDRESS, 1608)

    bobShares -= 1608
    bobAssets -= 2929
    totalStakedAssets -= 2929
    vaultAssets -= 2929
    totalSupply -= 1608

    await checkVaultState()

    // 9. All the Vault's assets and 1000 feesEscrow's assets are staked
    feesEscrowAssets -= 1000
    totalStakedAssets += 1000
    vaultAssets = 0

    await setBalance(vault.address, BigNumber.from(0))
    await setBalance(feesEscrow, BigNumber.from(feesEscrowAssets))
    await vault._setTotalStakedAssets(totalStakedAssets)

    await checkVaultState()

    // 10. Alice enters exit queue with 1000 shares
    let aliceExitQueueId = await vault
      .connect(alice)
      .callStatic.enterExitQueue(1000, alice.address, alice.address)
    await expect(vault.connect(alice).enterExitQueue(1000, alice.address, alice.address))
      .to.emit(vault, 'ExitQueueEnter')
      .withArgs(alice.address, alice.address, alice.address, aliceExitQueueId, 1000)

    aliceShares -= 1000
    aliceAssets -= 1822
    queuedShares += 1000
    expect(aliceExitQueueId).to.eq(latestExitQueueId)
    latestExitQueueId += 1000
    await checkVaultState()

    // 11. Bob enters exit queue with 4391 shares
    let bobExitQueueId = await vault
      .connect(bob)
      .callStatic.enterExitQueue(4391, bob.address, bob.address)
    await expect(vault.connect(bob).enterExitQueue(4391, bob.address, bob.address))
      .to.emit(vault, 'ExitQueueEnter')
      .withArgs(bob.address, bob.address, bob.address, bobExitQueueId, 4391)

    bobShares -= 4391
    bobAssets -= 7999
    queuedShares += 4391
    expect(bobExitQueueId).to.eq(latestExitQueueId)
    latestExitQueueId += 4391
    await checkVaultState()

    // 12. Update exit queue and transfer fees escrow assets to Bob and Alice
    await expect(vault.connect(other).updateExitQueue())
      .to.emit(exitQueue, 'CheckpointCreated')
      .withArgs(1427, 2600)

    feesEscrowAssets -= 2600
    totalSupply -= 1427
    queuedShares -= 1427
    unclaimedAssets += 2600
    vaultAssets += 2600
    await checkVaultState()

    // 13. Vault mutates by +5000 tokens
    feesEscrowAssets += 3000
    totalStakedAssets += 2000
    await setBalance(feesEscrow, BigNumber.from(feesEscrowAssets))
    await vault.connect(receiver)._setTotalStakedAssets(totalStakedAssets)

    aliceAssets += 1007
    await checkVaultState()

    // 14. Bob claims exited assets
    let bobCheckpointIdx = await vault.getCheckpointIndex(bobExitQueueId)
    await expect(
      vault.connect(bob).claimExitedAssets(bob.address, bobExitQueueId, bobCheckpointIdx)
    )
      .to.emit(vault, 'ExitedAssetsClaim')
      .withArgs(bob.address, bob.address, bobExitQueueId, 1427, 777)

    bobExitQueueId = BigNumber.from(1427)
    vaultAssets -= 777
    unclaimedAssets -= 777
    expect(bobCheckpointIdx).to.eq(0)
    await checkVaultState()

    // 15. Alice claims exited assets
    let aliceCheckpointIdx = await vault.getCheckpointIndex(aliceExitQueueId)
    await expect(
      vault.connect(alice).claimExitedAssets(alice.address, aliceExitQueueId, aliceCheckpointIdx)
    )
      .to.emit(vault, 'ExitedAssetsClaim')
      .withArgs(alice.address, alice.address, aliceExitQueueId, 0, 1822)

    aliceExitQueueId = BigNumber.from(0)
    vaultAssets -= 1822
    unclaimedAssets -= 1822
    expect(aliceCheckpointIdx).to.eq(0)
    await checkVaultState()

    // 16. Update exit queue and transfer fees escrow assets to Bob
    await increaseTime(ONE_DAY)
    await expect(vault.connect(other).updateExitQueue())
      .to.emit(exitQueue, 'CheckpointCreated')
      .withArgs(2487, 3000)

    feesEscrowAssets -= 3000
    totalSupply -= 1060
    queuedShares -= 1060
    unclaimedAssets += 3000
    vaultAssets += 3000
    await checkVaultState()

    // 17. Alice enters exit queue with 1000 shares
    aliceExitQueueId = await vault
      .connect(alice)
      .callStatic.enterExitQueue(1000, alice.address, alice.address)
    await expect(vault.connect(alice).enterExitQueue(1000, alice.address, alice.address))
      .to.emit(vault, 'ExitQueueEnter')
      .withArgs(alice.address, alice.address, alice.address, aliceExitQueueId, 1000)

    expect(aliceExitQueueId).to.be.eq(latestExitQueueId)
    latestExitQueueId += 1000
    queuedShares += 1000
    aliceShares -= 1000
    aliceAssets -= 2828
    await checkVaultState()

    // 18. Withdrawal of 11050 ETH arrives
    await increaseTime(ONE_DAY)
    await setBalance(vault.address, BigNumber.from(11050 + vaultAssets))
    await expect(vault.connect(other).updateExitQueue())
      .to.emit(exitQueue, 'CheckpointCreated')
      .withArgs(6391, 11043)

    vaultAssets += 11050
    totalSupply -= 3904
    queuedShares -= 3904
    totalStakedAssets -= 11043
    unclaimedAssets += 11043
    await checkVaultState()

    // 19. Bob claims exited assets
    bobCheckpointIdx = await vault.getCheckpointIndex(bobExitQueueId)
    expect(bobCheckpointIdx).to.eq(1)
    await expect(
      vault.connect(bob).claimExitedAssets(bob.address, bobExitQueueId, bobCheckpointIdx)
    )
      .to.emit(vault, 'ExitedAssetsClaim')
      .withArgs(bob.address, bob.address, bobExitQueueId, 0, 11214)

    unclaimedAssets -= 11214
    vaultAssets -= 11214
    await checkVaultState()

    // 20. Alice claims exited assets
    aliceCheckpointIdx = await vault.getCheckpointIndex(aliceExitQueueId)
    expect(aliceCheckpointIdx).to.eq(2)
    await expect(
      vault.connect(alice).claimExitedAssets(alice.address, aliceExitQueueId, aliceCheckpointIdx)
    )
      .to.emit(vault, 'ExitedAssetsClaim')
      .withArgs(alice.address, alice.address, aliceExitQueueId, 0, 2828)

    unclaimedAssets -= 2828
    vaultAssets -= 2828
    await checkVaultState()

    // 21. Check whether state is correct
    aliceShares = 0
    aliceAssets = 0
    bobShares = 0
    bobAssets = 0
    feesEscrowAssets = 0
    totalStakedAssets = 0
    totalSupply = 0
    queuedShares = 0
    unclaimedAssets = 2
    vaultAssets = 9
    await checkVaultState()
  })
})
