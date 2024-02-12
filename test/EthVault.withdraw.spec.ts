import { ethers } from 'hardhat'
import { Contract, parseEther, Signer, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  EthVault,
  IKeeperRewards,
  Keeper,
  SharedMevEscrow,
  VaultsRegistry,
  OsTokenVaultController,
  OsTokenConfig,
  EthVault__factory,
} from '../typechain-types'
import { ThenArg } from '../helpers/types'
import snapshotGasCost from './shared/snapshotGasCost'
import {
  deployEthVaultV1,
  encodeEthVaultInitParams,
  ethVaultFixture,
  upgradeVaultToV2,
} from './shared/fixtures'
import { expect } from './shared/expect'
import {
  EXITING_ASSETS_MIN_DELAY,
  ONE_DAY,
  PANIC_CODES,
  SECURITY_DEPOSIT,
  ZERO_ADDRESS,
} from './shared/constants'
import {
  extractDepositShares,
  extractExitPositionTicket,
  getBlockTimestamp,
  increaseTime,
  setBalance,
} from './shared/utils'
import {
  collateralizeEthV1Vault,
  getHarvestParams,
  getRewardsRootProof,
  updateRewards,
} from './shared/rewards'
import { getEthVaultV1Factory } from './shared/contracts'

const validatorDeposit = ethers.parseEther('32')

describe('EthVault - withdraw', () => {
  const capacity = ethers.parseEther('1000')
  const feePercent = 1000
  const referrer = '0x' + '1'.repeat(40)
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  let positionTicketV1: bigint, positionTicketV2: bigint
  let timestampV1: number, timestampV2: number
  let holderV1: Wallet, holderV2: Wallet, receiver: Wallet, admin: Signer, other: Wallet
  let holderV1Shares: bigint
  const holderV1Assets = parseEther('1')
  const holderV2Assets = parseEther('2')

  let vault: EthVault,
    keeper: Keeper,
    sharedMevEscrow: SharedMevEscrow,
    vaultsRegistry: VaultsRegistry,
    osTokenVaultController: OsTokenVaultController,
    osTokenConfig: OsTokenConfig,
    validatorsRegistry: Contract
  let vaultImpl: string

  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVault']
  let createVaultMock: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVaultMock']

  beforeEach('deploy fixture', async () => {
    ;[holderV1, holderV2, receiver, admin, other] = (await (ethers as any).getSigners()).slice(1, 6)
    const fixture = await loadFixture(ethVaultFixture)
    keeper = fixture.keeper
    validatorsRegistry = fixture.validatorsRegistry
    sharedMevEscrow = fixture.sharedMevEscrow
    createVault = fixture.createEthVault
    createVaultMock = fixture.createEthVaultMock
    vaultsRegistry = fixture.vaultsRegistry
    osTokenVaultController = fixture.osTokenVaultController
    osTokenConfig = fixture.osTokenConfig
    vaultImpl = await fixture.ethVaultFactory.implementation()

    const vaultV1 = await deployEthVaultV1(
      await getEthVaultV1Factory(),
      admin,
      keeper,
      vaultsRegistry,
      validatorsRegistry,
      osTokenVaultController,
      osTokenConfig,
      sharedMevEscrow,
      encodeEthVaultInitParams({
        capacity,
        feePercent,
        metadataIpfsHash,
      })
    )
    expect(await vaultV1.version()).to.be.eq(1)

    // create v1 position
    await collateralizeEthV1Vault(vaultV1, keeper, validatorsRegistry, admin)
    let tx = await vaultV1
      .connect(holderV1)
      .deposit(holderV1.address, referrer, { value: holderV1Assets })
    holderV1Shares = await extractDepositShares(tx)
    tx = await vaultV1.connect(holderV1).enterExitQueue(holderV1Shares, holderV1.address)
    positionTicketV1 = await extractExitPositionTicket(tx)
    timestampV1 = await getBlockTimestamp(tx)

    await upgradeVaultToV2(vaultV1, vaultImpl)
    vault = EthVault__factory.connect(await vaultV1.getAddress(), admin)
    expect(await vault.version()).to.be.eq(2)

    // create v2 position
    tx = await vault
      .connect(holderV2)
      .deposit(holderV2.address, referrer, { value: holderV2Assets })
    tx = await vault
      .connect(holderV2)
      .enterExitQueue(await extractDepositShares(tx), holderV2.address)
    positionTicketV2 = await extractExitPositionTicket(tx)
    timestampV2 = await getBlockTimestamp(tx)
    expect(positionTicketV2).to.be.eq(positionTicketV1 + holderV1Shares)
  })

  it('works for not collateralized vault', async () => {
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
    let tx = await vault
      .connect(holderV2)
      .deposit(holderV2.address, referrer, { value: holderV2Assets })
    const shares = await extractDepositShares(tx)
    tx = await vault.connect(holderV2).enterExitQueue(shares, holderV2.address)
    const positionTicket = await extractExitPositionTicket(tx)
    const timestamp = await getBlockTimestamp(tx)
    await increaseTime(EXITING_ASSETS_MIN_DELAY)

    const balanceBefore = await ethers.provider.getBalance(holderV2.address)
    await expect(vault.connect(holderV2).claimExitedAssets(positionTicket, timestamp, 0n))
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(holderV2.address, 0n, holderV2Assets)
    expect(await ethers.provider.getBalance(holderV2.address)).to.be.greaterThan(
      balanceBefore + holderV2Assets - parseEther('0.0001') // gas
    )
  })

  describe('enter exit queue', () => {
    let holder: Wallet
    let holderShares: bigint
    const holderAssets = parseEther('3')

    beforeEach(async () => {
      holder = holderV2
      const tx = await vault
        .connect(holder)
        .deposit(holder.address, referrer, { value: holderAssets })
      holderShares = await extractDepositShares(tx)
    })

    it('fails with zero shares', async () => {
      await expect(
        vault.connect(holder).enterExitQueue(0, receiver.address)
      ).to.be.revertedWithCustomError(vault, 'InvalidShares')
    })

    it('fails for zero address receiver', async () => {
      await expect(
        vault.connect(holder).enterExitQueue(holderShares, ZERO_ADDRESS)
      ).to.be.revertedWithCustomError(vault, 'ZeroAddress')
    })

    it('fails when not harvested', async () => {
      const vaultReward = getHarvestParams(await vault.getAddress(), 0n, 0n)
      await updateRewards(keeper, [vaultReward])
      await updateRewards(keeper, [vaultReward])
      await expect(
        vault.connect(holder).enterExitQueue(holderShares, receiver.address)
      ).to.be.revertedWithCustomError(vault, 'NotHarvested')
    })

    it('fails for sender other than owner', async () => {
      await expect(
        vault.connect(other).enterExitQueue(holderShares, receiver.address)
      ).to.be.revertedWithPanic(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
    })

    it('fails for shares larger than balance', async () => {
      await expect(
        vault.connect(holder).enterExitQueue(holderShares + 1n, receiver.address)
      ).to.be.revertedWithPanic(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
    })

    it('locks assets for the time of exit', async () => {
      expect(await vault.totalExitingAssets()).to.be.eq(holderV2Assets)
      expect(await vault.getShares(holder.address)).to.be.eq(holderShares)
      expect(await vault.getShares(await vault.getAddress())).to.be.eq(SECURITY_DEPOSIT)

      const totalAssetsBefore = await vault.totalAssets()
      const totalSharesBefore = await vault.totalShares()

      const receipt = await vault.connect(holder).enterExitQueue(holderShares, receiver.address)
      const positionTicket = await extractExitPositionTicket(receipt)
      const timestamp = await getBlockTimestamp(receipt)
      await expect(receipt)
        .to.emit(vault, 'ExitQueueEntered')
        .withArgs(holder.address, receiver.address, positionTicket, holderAssets)

      expect(await vault.totalAssets()).to.be.eq(totalAssetsBefore - holderAssets)
      expect(await vault.totalShares()).to.be.eq(totalSharesBefore - holderShares)
      expect(await vault.totalExitingAssets()).to.be.eq(holderAssets + holderV2Assets)
      expect(await vault.getShares(holder.address)).to.be.eq(0)
      expect(await vault.getShares(await vault.getAddress())).to.be.eq(SECURITY_DEPOSIT)

      const result = await vault.calculateExitedAssets(
        receiver.address,
        positionTicket,
        timestamp,
        0
      )
      expect(result.exitedAssets).to.eq(0)
      expect(result.exitedTickets).to.eq(0)
      expect(result.leftTickets).to.eq(holderAssets)
      await snapshotGasCost(receipt)
    })
  })

  describe('calculate exited assets', () => {
    it('returns zero with invalid exit request', async () => {
      let result = await vault.calculateExitedAssets(
        other.address,
        positionTicketV1,
        timestampV1,
        0n
      )
      expect(result.leftTickets).to.eq(0)
      expect(result.exitedTickets).to.eq(0)
      expect(result.exitedAssets).to.eq(0)

      result = await vault.calculateExitedAssets(other.address, positionTicketV2, timestampV2, 0n)
      expect(result.leftTickets).to.eq(0)
      expect(result.exitedTickets).to.eq(0)
      expect(result.exitedAssets).to.eq(0)
    })

    it('returns zero when delay has not passed', async () => {
      let result = await vault.calculateExitedAssets(
        holderV1.address,
        positionTicketV1,
        timestampV1,
        0n
      )
      expect(result.leftTickets).to.eq(holderV1Shares)
      expect(result.exitedTickets).to.eq(0)
      expect(result.exitedAssets).to.eq(0)

      result = await vault.calculateExitedAssets(
        holderV2.address,
        positionTicketV2,
        timestampV2,
        0n
      )
      expect(result.leftTickets).to.eq(holderV2Assets)
      expect(result.exitedTickets).to.eq(0)
      expect(result.exitedAssets).to.eq(0)
    })

    it('returns zero with invalid checkpoint index', async () => {
      await increaseTime(EXITING_ASSETS_MIN_DELAY)
      const vaultAddress = await vault.getAddress()
      const vaultReward = getHarvestParams(vaultAddress, 0n, 0n)
      const tree = await updateRewards(keeper, [vaultReward])
      await vault.updateState({
        rewardsRoot: tree.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof: getRewardsRootProof(tree, vaultReward),
      })
      const chkIndex = await vault.getExitQueueIndex(positionTicketV1)
      const result = await vault.calculateExitedAssets(
        holderV1.address,
        positionTicketV1,
        timestampV1,
        chkIndex + 1n
      )
      expect(result.leftTickets).to.eq(holderV1Shares)
      expect(result.exitedTickets).to.eq(0)
      expect(result.exitedAssets).to.eq(0)
    })

    it('works with partial withdrawals', async () => {
      await increaseTime(EXITING_ASSETS_MIN_DELAY)
      const vaultAddress = await vault.getAddress()
      const vaultReward = getHarvestParams(vaultAddress, 0n, 0n)

      // no assets are available
      await setBalance(vaultAddress, 0n)
      let tree = await updateRewards(keeper, [vaultReward])
      await vault.updateState({
        rewardsRoot: tree.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof: getRewardsRootProof(tree, vaultReward),
      })
      expect(await vault.getExitQueueIndex(positionTicketV1)).to.eq(-1)
      expect(await vault.getExitQueueIndex(positionTicketV2)).to.eq(-1)
      expect(await vault.totalExitingAssets()).to.eq(holderV2Assets)
      let result = await vault.calculateExitedAssets(
        holderV2.address,
        positionTicketV2,
        timestampV2,
        0n
      )
      expect(result.leftTickets).to.eq(holderV2Assets)
      expect(result.exitedTickets).to.eq(0)
      expect(result.exitedAssets).to.eq(0)

      // only half of position v1 assets are available
      const halfHolderV1Assets = holderV1Assets / 2n
      const halfHolderV1Shares = holderV1Shares / 2n
      await setBalance(vaultAddress, halfHolderV1Assets)
      tree = await updateRewards(keeper, [vaultReward])
      await vault.updateState({
        rewardsRoot: tree.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof: getRewardsRootProof(tree, vaultReward),
      })
      let chkIndex = await vault.getExitQueueIndex(positionTicketV1)
      expect(chkIndex).to.be.greaterThan(0)
      result = await vault.calculateExitedAssets(
        holderV1.address,
        positionTicketV1,
        timestampV1,
        chkIndex
      )
      expect(result.leftTickets).to.eq(halfHolderV1Shares)
      expect(result.exitedTickets).to.eq(halfHolderV1Shares)
      expect(result.exitedAssets).to.eq(halfHolderV1Assets)

      expect(await vault.getExitQueueIndex(positionTicketV2)).to.eq(-1)
      result = await vault.calculateExitedAssets(
        holderV2.address,
        positionTicketV2,
        timestampV2,
        0n
      )
      expect(result.leftTickets).to.eq(holderV2Assets)
      expect(result.exitedTickets).to.eq(0)
      expect(result.exitedAssets).to.eq(0)

      // all position v1 assets are available
      await setBalance(vaultAddress, holderV1Assets)
      tree = await updateRewards(keeper, [vaultReward])
      await vault.updateState({
        rewardsRoot: tree.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof: getRewardsRootProof(tree, vaultReward),
      })
      chkIndex = await vault.getExitQueueIndex(positionTicketV1)
      expect(chkIndex).to.be.greaterThan(0)
      result = await vault.calculateExitedAssets(
        holderV1.address,
        positionTicketV1,
        timestampV1,
        chkIndex
      )
      expect(result.leftTickets).to.eq(0)
      expect(result.exitedTickets).to.eq(holderV1Shares)
      expect(result.exitedAssets).to.eq(holderV1Assets)

      expect(await vault.getExitQueueIndex(positionTicketV2)).to.eq(-1)
      result = await vault.calculateExitedAssets(
        holderV2.address,
        positionTicketV2,
        timestampV2,
        0n
      )
      expect(result.leftTickets).to.eq(holderV2Assets)
      expect(result.exitedTickets).to.eq(0)
      expect(result.exitedAssets).to.eq(0)

      // half holder v2 assets are available
      const halfHolderV2Assets = holderV2Assets / 2n
      await setBalance(vaultAddress, holderV1Assets + halfHolderV2Assets)
      tree = await updateRewards(keeper, [vaultReward])
      await vault.updateState({
        rewardsRoot: tree.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof: getRewardsRootProof(tree, vaultReward),
      })
      chkIndex = await vault.getExitQueueIndex(positionTicketV1)
      expect(chkIndex).to.be.greaterThan(0)
      result = await vault.calculateExitedAssets(
        holderV1.address,
        positionTicketV1,
        timestampV1,
        chkIndex
      )
      expect(result.leftTickets).to.eq(0)
      expect(result.exitedTickets).to.eq(holderV1Shares)
      expect(result.exitedAssets).to.eq(holderV1Assets)

      expect(await vault.getExitQueueIndex(positionTicketV2)).to.eq(0)
      result = await vault.calculateExitedAssets(
        holderV2.address,
        positionTicketV2,
        timestampV2,
        0n
      )
      expect(result.leftTickets).to.eq(halfHolderV2Assets)
      expect(result.exitedTickets).to.eq(halfHolderV2Assets)
      expect(result.exitedAssets).to.eq(halfHolderV2Assets)

      // holder v2 all assets are available
      await setBalance(vaultAddress, holderV1Assets + holderV2Assets)
      tree = await updateRewards(keeper, [vaultReward])
      await vault.updateState({
        rewardsRoot: tree.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof: getRewardsRootProof(tree, vaultReward),
      })
      chkIndex = await vault.getExitQueueIndex(positionTicketV1)
      expect(chkIndex).to.be.greaterThan(0)
      result = await vault.calculateExitedAssets(
        holderV1.address,
        positionTicketV1,
        timestampV1,
        chkIndex
      )
      expect(result.leftTickets).to.eq(0)
      expect(result.exitedTickets).to.eq(holderV1Shares)
      expect(result.exitedAssets).to.eq(holderV1Assets)

      expect(await vault.getExitQueueIndex(positionTicketV2)).to.eq(0)
      result = await vault.calculateExitedAssets(
        holderV2.address,
        positionTicketV2,
        timestampV2,
        0n
      )
      expect(result.leftTickets).to.eq(0)
      expect(result.exitedTickets).to.eq(holderV2Assets)
      expect(result.exitedAssets).to.eq(holderV2Assets)
    })
  })

  describe('update exit queue', () => {
    let vault: Contract
    let holder: Wallet, admin: Wallet
    let holderShares: bigint
    const holderAssets = parseEther('3')
    let harvestParams: IKeeperRewards.HarvestParamsStruct
    let positionTicket: bigint

    beforeEach(async () => {
      holder = holderV1
      admin = receiver
      vault = await deployEthVaultV1(
        await getEthVaultV1Factory(),
        admin,
        keeper,
        vaultsRegistry,
        validatorsRegistry,
        osTokenVaultController,
        osTokenConfig,
        sharedMevEscrow,
        encodeEthVaultInitParams({
          capacity,
          feePercent,
          metadataIpfsHash,
        })
      )
      await collateralizeEthV1Vault(vault, keeper, validatorsRegistry, admin)
      let tx = await vault
        .connect(holder)
        .deposit(holder.address, referrer, { value: holderAssets })
      holderShares = await extractDepositShares(tx)
      const vaultReward = getHarvestParams(await vault.getAddress(), 0n, 0n)
      const tree = await updateRewards(keeper, [vaultReward])
      harvestParams = {
        rewardsRoot: tree.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof: getRewardsRootProof(tree, vaultReward),
      }
      tx = await vault.connect(holder).enterExitQueue(holderShares, holder.address)
      positionTicket = await extractExitPositionTicket(tx)
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
      const vaultReward = getHarvestParams(await vault.getAddress(), penalty, 0n)
      const tree = await updateRewards(keeper, [vaultReward])
      await expect(
        vault.updateState({
          rewardsRoot: tree.root,
          reward: vaultReward.reward,
          unlockedMevReward: vaultReward.unlockedMevReward,
          proof: getRewardsRootProof(tree, vaultReward),
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

    it('get checkpoint index works with many checkpoints', async () => {
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
      const chkIndex = await vault.getExitQueueIndex(positionTicket)
      expect(chkIndex).to.be.greaterThan(0)
    })
  })

  describe('claim exited assets', () => {
    let harvestParams: IKeeperRewards.HarvestParamsStruct

    beforeEach(async () => {
      const vaultReward = getHarvestParams(await vault.getAddress(), 0n, 0n)
      const tree = await updateRewards(keeper, [vaultReward])
      harvestParams = {
        rewardsRoot: tree.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof: getRewardsRootProof(tree, vaultReward),
      }
    })

    it('fails with invalid exit request', async () => {
      await increaseTime(EXITING_ASSETS_MIN_DELAY)
      await vault.updateState(harvestParams)
      let result = await vault.calculateExitedAssets(
        other.address,
        positionTicketV2,
        timestampV2,
        0n
      )
      expect(result.leftTickets).to.eq(0)
      expect(result.exitedTickets).to.eq(0)
      expect(result.exitedAssets).to.eq(0)
      await expect(
        vault.connect(other).claimExitedAssets(positionTicketV2, timestampV2, 0n)
      ).to.revertedWithCustomError(vault, 'ExitRequestNotProcessed')

      result = await vault.calculateExitedAssets(other.address, positionTicketV2, timestampV2, 0n)
      expect(result.leftTickets).to.eq(0)
      expect(result.exitedTickets).to.eq(0)
      expect(result.exitedAssets).to.eq(0)
      await expect(
        vault.connect(other).claimExitedAssets(positionTicketV2, timestampV2, 0n)
      ).to.revertedWithCustomError(vault, 'ExitRequestNotProcessed')
    })

    it('fails with invalid timestamp', async () => {
      await increaseTime(EXITING_ASSETS_MIN_DELAY)
      await vault.updateState(harvestParams)
      const result = await vault.calculateExitedAssets(
        other.address,
        positionTicketV2,
        timestampV2,
        0n
      )
      expect(result.leftTickets).to.eq(0)
      expect(result.exitedTickets).to.eq(0)
      expect(result.exitedAssets).to.eq(0)
      await expect(
        vault.connect(holderV2).claimExitedAssets(positionTicketV2, timestampV1, 0n)
      ).to.be.revertedWithCustomError(vault, 'ExitRequestNotProcessed')
    })

    it('fails when not harvested', async () => {
      await increaseTime(EXITING_ASSETS_MIN_DELAY)
      const vaultReward = getHarvestParams(await vault.getAddress(), 0n, 0n)
      await updateRewards(keeper, [vaultReward])
      await expect(
        vault.connect(holderV2).claimExitedAssets(positionTicketV2, timestampV2, 0n)
      ).to.be.revertedWithCustomError(vault, 'NotHarvested')
    })

    it('fails with invalid index', async () => {
      await increaseTime(EXITING_ASSETS_MIN_DELAY)
      await expect(
        vault.connect(holderV1).claimExitedAssets(positionTicketV1, timestampV1, 0n)
      ).to.be.revertedWithCustomError(vault, 'InvalidCheckpointIndex')
    })

    it('applies penalty when rate decreases', async () => {
      const halfHolderV2Assets = holderV2Assets / 2n
      const halfSecurityDeposit = SECURITY_DEPOSIT / 2n
      await increaseTime(EXITING_ASSETS_MIN_DELAY)
      // user v1 assets exited
      await vault.updateState(harvestParams)
      const vaultReward = getHarvestParams(await vault.getAddress(), -halfHolderV2Assets, 0n)
      const tree = await updateRewards(keeper, [vaultReward])
      await vault.updateState({
        rewardsRoot: tree.root,
        unlockedMevReward: vaultReward.unlockedMevReward,
        reward: vaultReward.reward,
        proof: getRewardsRootProof(tree, vaultReward),
      })

      await expect(
        vault
          .connect(holderV1)
          .claimExitedAssets(
            positionTicketV1,
            timestampV1,
            await vault.getExitQueueIndex(positionTicketV1)
          )
      )
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(holderV1.address, 0n, holderV1Assets)
      await expect(vault.connect(holderV2).claimExitedAssets(positionTicketV2, timestampV2, 0n))
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(holderV2.address, 0n, halfHolderV2Assets + halfSecurityDeposit)
      expect(await vault.totalExitingAssets()).to.be.eq(0)
    })

    it('applies penalty to all exiting assets', async () => {
      const vault = await createVaultMock(admin as Wallet, {
        capacity,
        feePercent: 0,
        metadataIpfsHash,
      })
      await vault.resetSecurityDeposit()
      let tx = await vault.deposit(holderV2.address, referrer, { value: holderV2Assets })
      const shares = await extractDepositShares(tx)
      tx = await vault.connect(holderV2).enterExitQueue(shares, holderV2.address)
      const positionTicket = await extractExitPositionTicket(tx)
      const timestamp = await getBlockTimestamp(tx)
      await increaseTime(EXITING_ASSETS_MIN_DELAY)

      expect(await vault.totalExitingAssets()).to.be.eq(holderV2Assets)
      expect(await vault.getShares(holderV2.address)).to.be.eq(0)
      expect(await vault.getShares(await vault.getAddress())).to.be.eq(0)
      expect(await vault.totalAssets()).to.be.eq(0)
      expect(await vault.totalShares()).to.be.eq(0)

      // penalty received
      const halfHolderV2Assets = holderV2Assets / 2n
      const vaultReward = getHarvestParams(await vault.getAddress(), -halfHolderV2Assets, 0n)
      const tree = await updateRewards(keeper, [vaultReward])
      await vault.updateState({
        rewardsRoot: tree.root,
        unlockedMevReward: vaultReward.unlockedMevReward,
        reward: vaultReward.reward,
        proof: getRewardsRootProof(tree, vaultReward),
      })

      await expect(
        vault
          .connect(holderV2)
          .claimExitedAssets(
            positionTicket,
            timestamp,
            await vault.getExitQueueIndex(positionTicket)
          )
      )
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(holderV2.address, 0n, halfHolderV2Assets)
      expect(await vault.totalExitingAssets()).to.be.eq(0)
    })

    it('for single user in single checkpoint', async () => {
      await vault.updateState(harvestParams)
      const checkpointIndex = await vault.getExitQueueIndex(positionTicketV1)
      await increaseTime(EXITING_ASSETS_MIN_DELAY)

      const holderV1AssetsBefore = await ethers.provider.getBalance(holderV1.address)
      const receipt = await vault
        .connect(holderV1)
        .claimExitedAssets(positionTicketV1, timestampV1, checkpointIndex)
      await expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(holderV1.address, 0, holderV1Assets)
      const tx = (await receipt.wait()) as any
      const gasUsed = BigInt(tx.cumulativeGasUsed * tx.gasPrice)
      expect(await ethers.provider.getBalance(holderV1.address)).to.be.eq(
        holderV1AssetsBefore + holderV1Assets - gasUsed
      )

      await snapshotGasCost(receipt)
    })

    it('for single user in multiple checkpoints in single transaction', async () => {
      const halfHolderAssets = holderV1Assets / 2n
      const halfHolderShares = holderV1Shares / 2n

      // create two checkpoints
      await setBalance(await vault.getAddress(), halfHolderAssets)
      await expect(vault.updateState(harvestParams))
        .to.emit(vault, 'CheckpointCreated')
        .withArgs(halfHolderShares, halfHolderAssets)
      const checkpointIndex = await vault.getExitQueueIndex(positionTicketV1)

      await increaseTime(ONE_DAY)
      await setBalance(await vault.getAddress(), holderV1Assets)
      const vaultReward = getHarvestParams(await vault.getAddress(), 0n, 0n)
      await updateRewards(keeper, [vaultReward])
      await expect(vault.updateState(harvestParams))
        .to.emit(vault, 'CheckpointCreated')
        .withArgs(halfHolderShares, halfHolderAssets)

      await increaseTime(EXITING_ASSETS_MIN_DELAY)
      const holderV1AssetsBefore = await ethers.provider.getBalance(holderV1.address)
      const receipt = await vault
        .connect(holderV1)
        .claimExitedAssets(positionTicketV1, timestampV1, checkpointIndex)

      await expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(holderV1.address, 0, holderV1Assets)

      const tx = (await receipt.wait()) as any
      const gasUsed = BigInt(tx.cumulativeGasUsed * tx.gasPrice)
      expect(await ethers.provider.getBalance(holderV1.address)).to.be.eq(
        holderV1AssetsBefore + holderV1Assets - gasUsed
      )
      expect(await ethers.provider.getBalance(await vault.getAddress())).to.be.eq(0)

      await snapshotGasCost(receipt)
    })

    it('for single user in multiple checkpoints in multiple transactions', async () => {
      const halfHolderAssets = holderV1Assets / 2n
      const halfHolderShares = holderV1Shares / 2n

      // create first checkpoint
      await setBalance(await vault.getAddress(), halfHolderAssets)
      await expect(vault.updateState(harvestParams))
        .to.emit(vault, 'CheckpointCreated')
        .withArgs(halfHolderShares, halfHolderAssets)
      const checkpointIndex = await vault.getExitQueueIndex(positionTicketV1)
      await increaseTime(EXITING_ASSETS_MIN_DELAY)

      const holderV1AssetsBefore = await ethers.provider.getBalance(holderV1.address)
      let receipt = await vault
        .connect(holderV1)
        .claimExitedAssets(positionTicketV1, timestampV1, checkpointIndex)

      const newPositionTicket = validatorDeposit + halfHolderShares
      await expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(holderV1.address, newPositionTicket, halfHolderAssets)

      let tx = (await receipt.wait()) as any
      let gasUsed = BigInt(tx.cumulativeGasUsed * tx.gasPrice)
      expect(await ethers.provider.getBalance(holderV1.address)).to.be.eq(
        holderV1AssetsBefore + halfHolderAssets - gasUsed
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
        .connect(holderV1)
        .claimExitedAssets(newPositionTicket, timestampV1, newCheckpointIndex)
      await expect(receipt)
        .to.emit(vault, 'ExitedAssetsClaimed')
        .withArgs(holderV1.address, 0, halfHolderAssets)

      tx = (await receipt.wait()) as any
      gasUsed += BigInt(tx.cumulativeGasUsed * tx.gasPrice)
      expect(await ethers.provider.getBalance(holderV1.address)).to.be.eq(
        holderV1AssetsBefore + holderV1Assets - gasUsed
      )
      expect(await ethers.provider.getBalance(await vault.getAddress())).to.be.eq(0)

      await snapshotGasCost(receipt)
    })

    it('for multiple users in single checkpoint', async () => {
      const admin = holderV2
      const vault = await deployEthVaultV1(
        await getEthVaultV1Factory(),
        admin,
        keeper,
        vaultsRegistry,
        validatorsRegistry,
        osTokenVaultController,
        osTokenConfig,
        sharedMevEscrow,
        encodeEthVaultInitParams({
          capacity,
          feePercent,
          metadataIpfsHash,
        })
      )
      await collateralizeEthV1Vault(vault, keeper, validatorsRegistry, admin)

      const shares = parseEther('1')
      const assets = parseEther('1')
      const user1 = holderV1
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
      const vaultReward = getHarvestParams(await vault.getAddress(), 0n, 0n)
      const tree = await updateRewards(keeper, [vaultReward])
      const harvestParams = {
        rewardsRoot: tree.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof: getRewardsRootProof(tree, vaultReward),
      }
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
    const alice = holderV1
    const bob = holderV2
    let sharedMevEscrowBalance = await ethers.provider.getBalance(
      await sharedMevEscrow.getAddress()
    )

    // collateralize vault by registering validator
    await vault._setTotalAssets(0)
    await vault._setTotalShares(0)

    let aliceShares = 0n
    let aliceAssets = 0n
    let bobShares = 0n
    let bobAssets = 0n
    let totalAssets = 0n
    let totalShares = 0n
    let totalExitingAssets = 0n
    let latestPositionTicket = 0n
    let vaultLiquidAssets = 0n
    let totalReward = 0n
    let totalUnlockedMevReward = 0n

    const checkVaultState = async () => {
      expect(await vault.getShares(alice.address)).to.be.eq(aliceShares, 'Alice shares mismatch')
      expect(await vault.getShares(bob.address)).to.be.eq(bobShares, 'Bob shares mismatch')
      expect(await vault.convertToAssets(aliceShares)).to.be.eq(
        aliceAssets,
        'Alice convertToAssets mismatch'
      )
      expect(await vault.convertToAssets(bobShares)).to.be.eq(
        bobAssets,
        'Bob convertToAssets mismatch'
      )
      expect(await vault.totalShares()).to.be.eq(totalShares, 'Total shares mismatch')
      expect(await ethers.provider.getBalance(await sharedMevEscrow.getAddress())).to.be.eq(
        sharedMevEscrowBalance,
        'Shared MEV escrow balance mismatch'
      )
      expect(await ethers.provider.getBalance(await vault.getAddress())).to.be.eq(
        vaultLiquidAssets,
        'Vault liquid assets mismatch'
      )
      expect(await vault.totalAssets()).to.be.eq(totalAssets, 'Total assets mismatch')
      expect(await vault.totalExitingAssets()).to.be.eq(
        totalExitingAssets,
        'Total exiting assets mismatch'
      )
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
    let vaultReward = getHarvestParams(
      await vault.getAddress(),
      totalReward,
      totalUnlockedMevReward
    )
    let tree = await updateRewards(keeper, [vaultReward])
    let proof = getRewardsRootProof(tree, vaultReward)
    await setBalance(await sharedMevEscrow.getAddress(), 1800n)
    await vault.updateState({
      rewardsRoot: tree.root,
      reward: vaultReward.reward,
      unlockedMevReward: vaultReward.unlockedMevReward,
      proof,
    })
    aliceAssets += 1000n
    bobAssets += 2000n
    sharedMevEscrowBalance = 0n

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
    vaultReward = getHarvestParams(await vault.getAddress(), totalReward, totalUnlockedMevReward)
    tree = await updateRewards(keeper, [vaultReward])
    proof = getRewardsRootProof(tree, vaultReward)
    await vault.updateState({
      rewardsRoot: tree.root,
      reward: vaultReward.reward,
      unlockedMevReward: vaultReward.unlockedMevReward,
      proof,
    })

    aliceAssets += 1071n
    bobAssets += 1929n

    await checkVaultState()

    // 7. Alice enters exit queue with 1333 shares (2427 assets)
    let response = await vault.connect(alice).enterExitQueue(1333, alice.address)
    let alicePositionTicket = await extractExitPositionTicket(response)
    let aliceTimestamp = await getBlockTimestamp(response)

    aliceShares -= 1333n
    aliceAssets -= 2427n
    totalAssets -= 2427n
    totalExitingAssets += 2427n
    totalShares -= 1333n
    expect(alicePositionTicket).to.eq(latestPositionTicket)
    latestPositionTicket = 2427n

    await checkVaultState()

    // 8. Alice withdraws assets
    await increaseTime(EXITING_ASSETS_MIN_DELAY)
    expect(await vault.getExitQueueIndex(alicePositionTicket)).to.be.eq(0)
    await vault.connect(alice).claimExitedAssets(alicePositionTicket, aliceTimestamp, 0n)

    vaultLiquidAssets -= 2427n
    totalExitingAssets -= 2427n

    await checkVaultState()

    // 9. Bob enters exit queue with 1608 shares (2928 assets)
    response = await vault.connect(bob).enterExitQueue(1608, bob.address)
    let bobPositionTicket = await extractExitPositionTicket(response)
    let bobTimestamp = await getBlockTimestamp(response)

    bobShares -= 1608n
    bobAssets -= 2928n
    totalAssets -= 2928n
    totalExitingAssets += 2928n
    totalShares -= 1608n
    expect(bobPositionTicket).to.eq(latestPositionTicket)
    latestPositionTicket = latestPositionTicket + 2928n

    await checkVaultState()

    // 10. Bob withdraws assets
    await increaseTime(EXITING_ASSETS_MIN_DELAY)
    expect(await vault.getExitQueueIndex(bobPositionTicket)).to.be.eq(0)
    await vault.connect(bob).claimExitedAssets(bobPositionTicket, bobTimestamp, 0n)
    vaultLiquidAssets -= 2928n
    totalExitingAssets -= 2928n
    await checkVaultState()

    // 11. Most the Vault's assets are staked
    vaultLiquidAssets = 2600n
    await setBalance(await vault.getAddress(), 2600n)
    await checkVaultState()

    // 12. Alice enters exit queue with 1000 shares (1821 assets)
    response = await vault.connect(alice).enterExitQueue(1000, alice.address)
    alicePositionTicket = await extractExitPositionTicket(response)
    aliceTimestamp = await getBlockTimestamp(response)
    await expect(response)
      .to.emit(vault, 'ExitQueueEntered')
      .withArgs(alice.address, alice.address, alicePositionTicket, 1821)

    aliceShares -= 1000n
    totalShares -= 1000n
    totalAssets -= 1821n
    aliceAssets -= 1821n
    totalExitingAssets += 1821n
    expect(alicePositionTicket).to.eq(latestPositionTicket)
    latestPositionTicket = latestPositionTicket + 1821n

    await checkVaultState()

    // 13. Bob enters exit queue with 4393 shares (8000 assets)
    response = await vault.connect(bob).enterExitQueue(4393n, bob.address)
    bobPositionTicket = await extractExitPositionTicket(response)
    bobTimestamp = await getBlockTimestamp(response)

    await expect(response)
      .to.emit(vault, 'ExitQueueEntered')
      .withArgs(bob.address, bob.address, bobPositionTicket, 8000)

    aliceAssets += 1n // rounding error
    bobShares -= 4393n
    bobAssets -= 8000n
    totalShares -= 4393n
    totalAssets -= 8000n
    totalExitingAssets += 8000n
    expect(bobPositionTicket).to.eq(latestPositionTicket)
    latestPositionTicket = latestPositionTicket + 8000n

    await checkVaultState()

    // 14. Vault mutates by +5000 assets
    totalAssets += 5000n
    totalReward += 5000n
    aliceAssets += 5000n
    vaultLiquidAssets += 3000n
    totalUnlockedMevReward += 3000n

    vaultReward = getHarvestParams(await vault.getAddress(), totalReward, totalUnlockedMevReward)
    tree = await updateRewards(keeper, [vaultReward])
    await setBalance(await sharedMevEscrow.getAddress(), 3000n)
    await vault.updateState({
      rewardsRoot: tree.root,
      reward: vaultReward.reward,
      unlockedMevReward: vaultReward.unlockedMevReward,
      proof: getRewardsRootProof(tree, vaultReward),
    })

    await checkVaultState()

    // 14. Bob claims exited assets
    await increaseTime(EXITING_ASSETS_MIN_DELAY)
    let bobCheckpointIdx = await vault.getExitQueueIndex(bobPositionTicket)
    await expect(
      vault.connect(bob).claimExitedAssets(bobPositionTicket, bobTimestamp, bobCheckpointIdx)
    )
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(bob.address, bobPositionTicket + 3779n, 3779n)

    bobPositionTicket += 3779n
    vaultLiquidAssets -= 3779n
    totalExitingAssets -= 3779n
    await checkVaultState()

    // 16. Alice claims exited assets
    let aliceCheckpointIdx = await vault.getExitQueueIndex(alicePositionTicket)
    await expect(
      vault
        .connect(alice)
        .claimExitedAssets(alicePositionTicket, aliceTimestamp, aliceCheckpointIdx)
    )
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(alice.address, 0n, 1821)

    vaultLiquidAssets -= 1821n
    totalExitingAssets -= 1821n
    await checkVaultState()

    // 17. Alice enters exit queue with 1001 shares
    response = await vault.connect(alice).enterExitQueue(1001, alice.address)
    alicePositionTicket = await extractExitPositionTicket(response)
    aliceTimestamp = await getBlockTimestamp(response)
    await expect(response)
      .to.emit(vault, 'ExitQueueEntered')
      .withArgs(alice.address, alice.address, latestPositionTicket, 6824n)

    expect(alicePositionTicket).to.be.eq(latestPositionTicket)
    aliceShares -= 1001n
    aliceAssets -= 6824n
    totalShares -= 1001n
    totalAssets -= 6824n
    totalExitingAssets += 6824n
    await checkVaultState()

    // 17. Withdrawal of all the assets arrives
    await setBalance(await vault.getAddress(), totalExitingAssets)
    vaultLiquidAssets = totalExitingAssets

    await checkVaultState()

    // 19. Bob claims exited assets
    await increaseTime(EXITING_ASSETS_MIN_DELAY)
    bobCheckpointIdx = await vault.getExitQueueIndex(bobPositionTicket)
    await expect(
      vault.connect(bob).claimExitedAssets(bobPositionTicket, bobTimestamp, bobCheckpointIdx)
    )
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(bob.address, 0, 4221)

    vaultLiquidAssets -= 4221n
    totalExitingAssets -= 4221n
    await checkVaultState()

    // 20. Alice claims exited assets
    aliceCheckpointIdx = await vault.getExitQueueIndex(alicePositionTicket)
    await expect(
      vault
        .connect(alice)
        .claimExitedAssets(alicePositionTicket, aliceTimestamp, aliceCheckpointIdx)
    )
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(alice.address, 0, 6824)
    vaultLiquidAssets -= 6824n
    totalExitingAssets -= 6824n
    await checkVaultState()

    // 20. Check whether state is correct
    aliceShares = 0n
    aliceAssets = 0n
    bobShares = 0n
    bobAssets = 0n
    totalAssets = 0n
    totalShares = 0n
    vaultLiquidAssets = 0n
    await checkVaultState()
  })
})
