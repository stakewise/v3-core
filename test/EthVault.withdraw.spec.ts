import { ethers, waffle } from 'hardhat'
import { BigNumber, Contract, Wallet } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import {
  Keeper,
  EthVault,
  EthVaultMock,
  Oracles,
  IKeeperRewards,
  SharedMevEscrow,
} from '../typechain-types'
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
  const name = 'SW ETH Vault'
  const symbol = 'SW-ETH-1'
  const referrer = '0x' + '1'.repeat(40)
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  const holderShares = parseEther('1')
  const holderAssets = parseEther('1')

  let holder: Wallet, receiver: Wallet, admin: Wallet, dao: Wallet, other: Wallet
  let vault: EthVault,
    keeper: Keeper,
    oracles: Oracles,
    sharedMevEscrow: SharedMevEscrow,
    validatorsRegistry: Contract
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
    ;({
      createVault,
      createVaultMock,
      getSignatures,
      keeper,
      oracles,
      validatorsRegistry,
      sharedMevEscrow,
    } = await loadFixture(ethVaultFixture))
    vault = await createVault(admin, {
      capacity,
      feePercent,
      name,
      symbol,
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
      unlockedMevReward: 0,
      proof,
    }

    await vault.connect(holder).deposit(holder.address, referrer, { value: holderAssets })
  })

  describe('redeem', () => {
    it('fails with not enough balance', async () => {
      await setBalance(vault.address, BigNumber.from(0))
      await expect(
        vault.connect(holder).redeem(holderShares, receiver.address, holder.address)
      ).to.be.revertedWith('InsufficientAssets')
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

    it('fails for zero address receiver', async () => {
      const newBalance = holderShares.add(1)
      await setBalance(vault.address, newBalance)
      await expect(
        vault.connect(holder).redeem(newBalance, ZERO_ADDRESS, holder.address)
      ).to.be.revertedWith('ZeroAddress')
    })

    it('fails for not harvested vault', async () => {
      await vault.updateState(harvestParams)
      await updateRewards(keeper, oracles, getSignatures, [
        { vault: vault.address, reward: 1, unlockedMevReward: 0 },
      ])
      await updateRewards(keeper, oracles, getSignatures, [
        { vault: vault.address, reward: 2, unlockedMevReward: 0 },
      ])
      await expect(
        vault.connect(holder).redeem(holderShares, receiver.address, holder.address)
      ).to.be.revertedWith('NotHarvested')
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
        feePercent,
        name,
        symbol,
        metadataIpfsHash,
      })
      await vault.resetSecurityDeposit()
      await vault.connect(holder).deposit(holder.address, referrer, { value: holderAssets })

      const receiverBalanceBefore = await waffle.provider.getBalance(receiver.address)

      await setBalance(await vault.address, MAX_UINT128)
      await vault._setTotalAssets(MAX_UINT128)

      await vault.connect(holder).redeem(holderShares, receiver.address, holder.address)
      expect(await vault.totalAssets()).to.be.eq(0)
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore.add(MAX_UINT128)
      )
    })

    it('redeem transfers assets to receiver', async () => {
      const receiverBalanceBefore = await waffle.provider.getBalance(receiver.address)
      const receipt = await vault
        .connect(holder)
        .redeem(holderShares, receiver.address, holder.address)
      await expect(receipt)
        .to.emit(vault, 'Redeem')
        .withArgs(holder.address, receiver.address, holder.address, holderAssets, holderShares)
      await expect(receipt)
        .to.emit(vault, 'Transfer')
        .withArgs(holder.address, ZERO_ADDRESS, holderShares)

      expect(await vault.totalAssets()).to.be.eq(SECURITY_DEPOSIT)
      expect(await vault.totalSupply()).to.be.eq(SECURITY_DEPOSIT)
      expect(await vault.balanceOf(holder.address)).to.be.eq(0)
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(SECURITY_DEPOSIT)
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore.add(holderAssets)
      )

      await snapshotGasCost(receipt)
    })

    it('fails with 0 shares', async () => {
      await expect(
        vault.connect(holder).redeem(0, receiver.address, holder.address)
      ).to.be.revertedWith('InvalidShares')
    })
  })

  describe('enter exit queue', () => {
    it('fails with 0 shares', async () => {
      await expect(
        vault.connect(holder).enterExitQueue(0, receiver.address, holder.address)
      ).to.be.revertedWith('InvalidSharesAmount')
    })

    it('fails for zero address receiver', async () => {
      await expect(
        vault.connect(holder).enterExitQueue(holderShares, ZERO_ADDRESS, holder.address)
      ).to.be.revertedWith('ZeroAddress')
    })

    it('fails for not collateralized', async () => {
      const newVault = await createVault(admin, {
        capacity,
        feePercent,
        name,
        symbol,
        metadataIpfsHash,
      })
      await newVault.connect(holder).deposit(holder.address, referrer, { value: holderAssets })
      await expect(
        newVault.connect(holder).enterExitQueue(holderShares, receiver.address, holder.address)
      ).to.be.revertedWith('NotCollateralized')
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
      expect(await vault.balanceOf(vault.address)).to.be.eq(SECURITY_DEPOSIT)

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
    beforeEach(async () => {
      await vault.connect(holder).enterExitQueue(holderShares, receiver.address, holder.address)
    })

    it('skips if it is too early', async () => {
      await vault.updateState(harvestParams)
      await vault.connect(holder).deposit(holder.address, referrer, { value: holderAssets })
      await vault.connect(holder).enterExitQueue(holderShares, receiver.address, holder.address)
      await expect(vault.updateState(harvestParams)).to.not.emit(vault, 'CheckpointCreated')
    })

    it('skips with 0 queued shares', async () => {
      await expect(vault.updateState(harvestParams)).to.emit(vault, 'CheckpointCreated')
      expect(await vault.queuedShares()).to.be.eq(0)
      await increaseTime(ONE_DAY)
      await expect(vault.updateState(harvestParams)).to.not.emit(vault, 'CheckpointCreated')
    })

    it('skips with 0 burned assets', async () => {
      const totalAssets = await vault.totalAssets()
      const penalty = totalAssets.sub(totalAssets.mul(2))
      const tree = await updateRewards(keeper, oracles, getSignatures, [
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
      expect(await vault.totalSupply()).to.be.eq(SECURITY_DEPOSIT)
      expect(await vault.totalAssets()).to.be.eq(SECURITY_DEPOSIT)
      expect(await vault.queuedShares()).to.be.eq(0)

      await snapshotGasCost(receipt)
    })
  })

  it('get checkpoint index works with many checkpoints', async () => {
    const vault: EthVaultMock = await createVaultMock(admin, {
      capacity,
      feePercent,
      name,
      symbol,
      metadataIpfsHash,
    })

    // collateralize vault by registering validator
    await vault.connect(holder).deposit(holder.address, referrer, { value: validatorDeposit })
    await registerEthValidator(vault, oracles, keeper, validatorsRegistry, admin, getSignatures)

    const positionTicket = await vault
      .connect(holder)
      .callStatic.enterExitQueue(holderShares, receiver.address, holder.address)
    await vault.connect(holder).enterExitQueue(holderShares, receiver.address, holder.address)

    // rewards tree updated
    const rewardsTree = await updateRewards(keeper, oracles, getSignatures, [
      { vault: vault.address, reward: 0, unlockedMevReward: 0 },
    ])
    const proof = getRewardsRootProof(rewardsTree, {
      vault: vault.address,
      reward: 0,
      unlockedMevReward: 0,
    })

    // create checkpoints every day for 10 years
    for (let i = 1; i <= 3650; i++) {
      await setBalance(vault.address, BigNumber.from(i))
      await increaseTime(ONE_DAY)
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
    let positionTicket

    beforeEach(async () => {
      positionTicket = await vault
        .connect(holder)
        .callStatic.enterExitQueue(holderShares, receiver.address, holder.address)
      await vault.connect(holder).enterExitQueue(holderShares, receiver.address, holder.address)
      receiverBalanceBefore = await waffle.provider.getBalance(receiver.address)
    })

    it('returns zero with no queued shares', async () => {
      await vault.updateState(harvestParams)
      const checkpointIndex = await vault.getExitQueueIndex(positionTicket)
      const result = await vault.callStatic.claimExitedAssets(
        other.address,
        positionTicket,
        checkpointIndex
      )
      expect(result.newPositionTicket).to.be.eq(positionTicket)
      expect(result.claimedAssets).to.be.eq(0)
      await expect(
        vault.connect(other).claimExitedAssets(other.address, positionTicket, checkpointIndex)
      ).to.not.emit(vault, 'ExitedAssetsClaimed')
    })

    it('returns -1 for unknown checkpoint index', async () => {
      expect(await vault.getExitQueueIndex(validatorDeposit)).to.be.eq(-1)
    })

    it('returns 0 with checkpoint index larger than checkpoints array', async () => {
      const result = await vault.callStatic.claimExitedAssets(receiver.address, positionTicket, 1)
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
        .callStatic.enterExitQueue(holderShares, receiver.address, holder.address)
      await vault.connect(holder).enterExitQueue(holderShares, receiver.address, holder.address)
      // checkpointIndex is lower than positionTicket
      await expect(
        vault.connect(holder).claimExitedAssets(receiver.address, positionTicket2, checkpointIndex)
      ).to.be.revertedWith('InvalidCheckpointIndex')
      await increaseTime(ONE_DAY)
      await vault.updateState(harvestParams)

      const positionTicket3 = await vault
        .connect(holder)
        .callStatic.enterExitQueue(holderShares, receiver.address, holder.address)
      await vault.connect(holder).enterExitQueue(holderShares, receiver.address, holder.address)
      await increaseTime(ONE_DAY)
      await vault.updateState(harvestParams)
      const checkpointIndexThree = await vault.getExitQueueIndex(positionTicket3)
      // checkpointIndex is higher than positionTicket
      await expect(
        vault
          .connect(holder)
          .claimExitedAssets(receiver.address, positionTicket, checkpointIndexThree)
      ).to.be.revertedWith('InvalidCheckpointIndex')
    })

    it('for single user in single checkpoint', async () => {
      await vault.updateState(harvestParams)
      const checkpointIndex = await vault.getExitQueueIndex(positionTicket)

      const receipt = await vault
        .connect(holder)
        .claimExitedAssets(receiver.address, positionTicket, checkpointIndex)
      await expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(holder.address, receiver.address, positionTicket, 0, holderAssets)
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore.add(holderAssets)
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
      await expect(vault.updateState(harvestParams))
        .to.emit(vault, 'CheckpointCreated')
        .withArgs(halfHolderShares, halfHolderAssets)

      const receipt = await vault
        .connect(holder)
        .claimExitedAssets(receiver.address, positionTicket, checkpointIndex)

      await expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(holder.address, receiver.address, positionTicket, 0, holderAssets)
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
        .to.emit(vault, 'CheckpointCreated')
        .withArgs(halfHolderShares, halfHolderAssets)
      const checkpointIndex = await vault.getExitQueueIndex(positionTicket)
      let receipt = await vault
        .connect(holder)
        .claimExitedAssets(receiver.address, positionTicket, checkpointIndex)

      const newPositionTicket = validatorDeposit.add(halfHolderShares)
      await expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(
          holder.address,
          receiver.address,
          positionTicket,
          newPositionTicket,
          halfHolderAssets
        )
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore.add(halfHolderAssets)
      )

      await snapshotGasCost(receipt)

      // create second checkpoint
      await increaseTime(ONE_DAY)
      await setBalance(vault.address, halfHolderAssets)
      await expect(vault.updateState(harvestParams))
        .to.emit(vault, 'CheckpointCreated')
        .withArgs(halfHolderShares, halfHolderAssets)

      const newCheckpointIndex = await vault.getExitQueueIndex(newPositionTicket)
      receipt = await vault
        .connect(holder)
        .claimExitedAssets(receiver.address, newPositionTicket, newCheckpointIndex)
      await expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(holder.address, receiver.address, newPositionTicket, 0, halfHolderAssets)
      expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(
        receiverBalanceBefore.add(holderAssets)
      )
      expect(await waffle.provider.getBalance(vault.address)).to.be.eq(0)

      await snapshotGasCost(receipt)
    })

    it('for multiple users in single checkpoint', async () => {
      // harvests the previous queued position
      await vault.updateState(harvestParams)
      const checkpointIndex = await vault.getExitQueueIndex(positionTicket)
      await vault
        .connect(holder)
        .claimExitedAssets(receiver.address, positionTicket, checkpointIndex)

      const shares = holderShares
      const assets = holderAssets
      const user1 = holder
      const user2 = receiver

      await vault.connect(user1).deposit(user1.address, referrer, { value: assets })
      await vault.connect(user2).deposit(user2.address, referrer, { value: assets })

      const user1PositionTicket = await vault
        .connect(user1)
        .callStatic.enterExitQueue(shares, user1.address, user1.address)
      await vault.connect(user1).enterExitQueue(shares, user1.address, user1.address)
      const user1BalanceBefore = await waffle.provider.getBalance(user1.address)

      const user2PositionTicket = await vault
        .connect(user2)
        .callStatic.enterExitQueue(shares, user2.address, user2.address)
      await vault.connect(user2).enterExitQueue(shares, user2.address, user2.address)
      const user2BalanceBefore = await waffle.provider.getBalance(user2.address)

      await increaseTime(ONE_DAY)
      await expect(vault.connect(other).updateState(harvestParams))
        .to.emit(vault, 'CheckpointCreated')
        .withArgs(shares.mul(2), assets.mul(2))

      let receipt = await vault
        .connect(other)
        .claimExitedAssets(
          user2.address,
          user2PositionTicket,
          await vault.getExitQueueIndex(user2PositionTicket)
        )
      await expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(other.address, user2.address, user2PositionTicket, 0, assets)
      expect(await waffle.provider.getBalance(user2.address)).to.be.eq(
        user2BalanceBefore.add(assets)
      )

      receipt = await vault
        .connect(other)
        .claimExitedAssets(
          user1.address,
          user1PositionTicket,
          await vault.getExitQueueIndex(user1PositionTicket)
        )
      await expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(other.address, user1.address, user1PositionTicket, 0, assets)
      expect(await waffle.provider.getBalance(user1.address)).to.be.eq(
        user1BalanceBefore.add(assets)
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
      name,
      symbol,
      metadataIpfsHash,
    })
    await vault.resetSecurityDeposit()
    const alice = holder
    const bob = other

    // collateralize vault by registering validator
    await collateralizeEthVault(vault, oracles, keeper, validatorsRegistry, admin, getSignatures)
    await vault._setTotalAssets(0)
    await vault._setTotalShares(0)

    let aliceShares = 0
    let aliceAssets = 0
    let bobShares = 0
    let bobAssets = 0
    let totalAssets = 0
    let totalSupply = 0
    let queuedShares = 0
    let unclaimedAssets = 0
    let latestPositionTicket = validatorDeposit
    let vaultLiquidAssets = 0
    let totalReward = 0
    let totalUnlockedMevReward = 0

    const checkVaultState = async () => {
      expect(await vault.balanceOf(alice.address)).to.be.eq(aliceShares)
      expect(await vault.balanceOf(bob.address)).to.be.eq(bobShares)
      expect(await vault.convertToAssets(aliceShares)).to.be.eq(aliceAssets)
      expect(await vault.convertToAssets(bobShares)).to.be.eq(bobAssets)
      expect(await vault.totalSupply()).to.be.eq(totalSupply)
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
    totalSupply += 2000
    await expect(vault.connect(alice).deposit(alice.address, referrer, { value: aliceAssets }))
      .to.emit(vault, 'Transfer')
      .withArgs(ZERO_ADDRESS, alice.address, aliceShares)

    await checkVaultState()

    // 2. Bob deposits 4000 ETH (mints 4000 shares)
    bobShares += 4000
    bobAssets += 4000
    totalAssets += 4000
    vaultLiquidAssets += 4000
    totalSupply += 4000
    await expect(vault.connect(bob).deposit(bob.address, referrer, { value: bobAssets }))
      .to.emit(vault, 'Transfer')
      .withArgs(ZERO_ADDRESS, bob.address, bobShares)

    await checkVaultState()

    // 3. Vault mutates by +3000 ETH (40% from validators, 60% from priority fees)
    totalAssets += 3000
    totalReward += 3000
    vaultLiquidAssets += 1800
    totalUnlockedMevReward += 1800
    let tree = await updateRewards(keeper, oracles, getSignatures, [
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

    // 4. Alice deposits 2000 ETH (mints 1333 shares)
    aliceShares += 1333
    aliceAssets += 1999 // rounds down
    totalAssets += 2000
    vaultLiquidAssets += 2000
    totalSupply += 1333

    await expect(vault.connect(alice).deposit(alice.address, referrer, { value: 2000 }))
      .to.emit(vault, 'Transfer')
      .withArgs(ZERO_ADDRESS, alice.address, 1333)

    await checkVaultState()

    // 5. Bob deposits 3000 ETH (mints 1999 shares)
    await expect(vault.connect(bob).deposit(bob.address, referrer, { value: 3000 }))
      .to.emit(vault, 'Transfer')
      .withArgs(ZERO_ADDRESS, bob.address, 1999)
    aliceAssets += 1 // rounds up
    bobShares += 1999 // rounds down
    bobAssets += 2999 // rounds down
    totalAssets += 3000
    vaultLiquidAssets += 3000
    totalSupply += 1999

    await checkVaultState()

    // 6. Vault mutates by +3000 tokens
    totalAssets += 3000
    totalReward += 3000
    vaultLiquidAssets += 1800
    totalUnlockedMevReward += 1800
    await setBalance(sharedMevEscrow.address, BigNumber.from(1800))
    tree = await updateRewards(keeper, oracles, getSignatures, [
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

    // 7. Alice redeems 1333 shares (2428 assets)
    await expect(vault.connect(alice).redeem(1333, alice.address, alice.address))
      .to.emit(vault, 'Transfer')
      .withArgs(alice.address, ZERO_ADDRESS, 1333)

    aliceShares -= 1333
    aliceAssets -= 2428
    totalAssets -= 2428
    vaultLiquidAssets -= 2428
    totalSupply -= 1333

    await checkVaultState()

    // 8. Bob withdraws 1608 assets (2929 shares)
    const receipt = await vault.connect(bob).redeem(1608, bob.address, bob.address)
    await expect(receipt).to.emit(vault, 'Transfer').withArgs(bob.address, ZERO_ADDRESS, 1608)

    bobShares -= 1608
    bobAssets -= 2929
    totalAssets -= 2929
    vaultLiquidAssets -= 2929
    totalSupply -= 1608

    await checkVaultState()

    // 9. Most the Vault's assets are staked
    vaultLiquidAssets = 2600
    await setBalance(vault.address, BigNumber.from(2600))

    await checkVaultState()

    // 10. Alice enters exit queue with 1000 shares
    let alicePositionTicket = await vault
      .connect(alice)
      .callStatic.enterExitQueue(1000, alice.address, alice.address)
    await expect(vault.connect(alice).enterExitQueue(1000, alice.address, alice.address))
      .to.emit(vault, 'ExitQueueEntered')
      .withArgs(alice.address, alice.address, alice.address, alicePositionTicket, 1000)

    aliceShares -= 1000
    aliceAssets -= 1822
    queuedShares += 1000
    expect(alicePositionTicket).to.eq(latestPositionTicket)
    latestPositionTicket = validatorDeposit.add(1000)

    await checkVaultState()

    // 11. Bob enters exit queue with 4391 shares
    let bobPositionTicket = await vault
      .connect(bob)
      .callStatic.enterExitQueue(4391, bob.address, bob.address)
    await expect(vault.connect(bob).enterExitQueue(4391, bob.address, bob.address))
      .to.emit(vault, 'ExitQueueEntered')
      .withArgs(bob.address, bob.address, bob.address, bobPositionTicket, 4391)

    bobShares -= 4391
    bobAssets -= 7999
    queuedShares += 4391
    expect(bobPositionTicket).to.eq(latestPositionTicket)
    latestPositionTicket = latestPositionTicket.add(4391)

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

    totalAssets -= 2600
    totalSupply -= 1427
    queuedShares -= 1427
    unclaimedAssets += 2600

    await checkVaultState()

    // 13. Vault mutates by +5000 tokens
    totalAssets += 5000
    totalReward += 5000
    vaultLiquidAssets += 3000
    totalUnlockedMevReward += 3000

    tree = await updateRewards(keeper, oracles, getSignatures, [
      { vault: vault.address, reward: totalReward, unlockedMevReward: totalUnlockedMevReward },
    ])
    await setBalance(sharedMevEscrow.address, BigNumber.from(3000))
    await vault.updateState({
      rewardsRoot: tree.root,
      reward: totalReward,
      unlockedMevReward: totalUnlockedMevReward,
      proof: getRewardsRootProof(tree, {
        vault: vault.address,
        reward: totalReward,
        unlockedMevReward: totalUnlockedMevReward,
      }),
    })

    // update alice assets
    aliceAssets += 1007

    await checkVaultState()

    // 14. Bob claims exited assets
    let bobCheckpointIdx = await vault.getExitQueueIndex(bobPositionTicket)
    await expect(
      vault.connect(bob).claimExitedAssets(bob.address, bobPositionTicket, bobCheckpointIdx)
    )
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(bob.address, bob.address, bobPositionTicket, bobPositionTicket.add(427), 777)

    bobPositionTicket = bobPositionTicket.add(427)
    vaultLiquidAssets -= 777
    unclaimedAssets -= 777
    expect(bobCheckpointIdx).to.eq(1)
    await checkVaultState()

    // 15. Alice claims exited assets
    let aliceCheckpointIdx = await vault.getExitQueueIndex(alicePositionTicket)
    await expect(
      vault.connect(alice).claimExitedAssets(alice.address, alicePositionTicket, aliceCheckpointIdx)
    )
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(alice.address, alice.address, alicePositionTicket, 0, 1822)

    vaultLiquidAssets -= 1822
    unclaimedAssets -= 1822
    expect(aliceCheckpointIdx).to.eq(1)

    await checkVaultState()

    // 16. Update exit queue and transfer assets to Bob
    await increaseTime(ONE_DAY)
    await expect(
      vault.updateState({
        rewardsRoot: tree.root,
        reward: totalReward,
        unlockedMevReward: totalUnlockedMevReward,
        proof,
      })
    )
      .to.emit(vault, 'CheckpointCreated')
      .withArgs(1060, 3000)

    totalAssets -= 3000
    totalSupply -= 1060
    queuedShares -= 1060
    unclaimedAssets += 3000
    await checkVaultState()

    // 17. Alice enters exit queue with 1000 shares
    alicePositionTicket = await vault
      .connect(alice)
      .callStatic.enterExitQueue(1000, alice.address, alice.address)
    await expect(vault.connect(alice).enterExitQueue(1000, alice.address, alice.address))
      .to.emit(vault, 'ExitQueueEntered')
      .withArgs(alice.address, alice.address, alice.address, alicePositionTicket, 1000)

    expect(alicePositionTicket).to.be.eq(latestPositionTicket)
    queuedShares += 1000
    aliceShares -= 1000
    aliceAssets -= 2828
    latestPositionTicket = latestPositionTicket.add(1000)
    await checkVaultState()

    // 18. Withdrawal of all the assets arrives
    await increaseTime(ONE_DAY)
    await setBalance(vault.address, BigNumber.from(totalAssets + unclaimedAssets))
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
    totalSupply = 0
    queuedShares = 0
    totalAssets = 0

    await checkVaultState()

    // 19. Bob claims exited assets
    bobCheckpointIdx = await vault.getExitQueueIndex(bobPositionTicket)
    expect(bobCheckpointIdx).to.eq(2)
    await expect(
      vault.connect(bob).claimExitedAssets(bob.address, bobPositionTicket, bobCheckpointIdx)
    )
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(bob.address, bob.address, bobPositionTicket, 0, 11214)

    vaultLiquidAssets -= 11214
    await checkVaultState()

    // 20. Alice claims exited assets
    aliceCheckpointIdx = await vault.getExitQueueIndex(alicePositionTicket)
    expect(aliceCheckpointIdx).to.eq(3)
    await expect(
      vault.connect(alice).claimExitedAssets(alice.address, alicePositionTicket, aliceCheckpointIdx)
    )
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(alice.address, alice.address, alicePositionTicket, 0, 2828)
    //
    vaultLiquidAssets -= 2828
    await checkVaultState()

    // 21. Check whether state is correct
    aliceShares = 0
    aliceAssets = 0
    bobShares = 0
    bobAssets = 0
    totalAssets = 0
    totalSupply = 0
    queuedShares = 0
    vaultLiquidAssets = 2
    await checkVaultState()
  })
})
