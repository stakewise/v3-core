import { ethers } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  ERC20Mock,
  GnoGenesisVault,
  Keeper,
  LegacyRewardTokenMock,
  PoolEscrowMock,
  DepositDataManager,
} from '../../typechain-types'
import { expect } from '../shared/expect'
import keccak256 from 'keccak256'
import {
  EXITING_ASSETS_MIN_DELAY,
  SECURITY_DEPOSIT,
  ZERO_ADDRESS,
  ZERO_BYTES32,
} from '../shared/constants'
import snapshotGasCost from '../shared/snapshotGasCost'
import { registerEthValidator } from '../shared/validators'
import { getHarvestParams, getRewardsRootProof, updateRewards } from '../shared/rewards'
import {
  extractDepositShares,
  extractExitPositionTicket,
  getBlockTimestamp,
  increaseTime,
} from '../shared/utils'
import { ThenArg } from '../../helpers/types'
import {
  collateralizeGnoVault,
  depositGno,
  gnoVaultFixture,
  setGnoWithdrawals,
} from '../shared/gnoFixtures'

describe('GnoGenesisVault', () => {
  const capacity = ethers.parseEther('1000000')
  const feePercent = 500
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  let admin: Wallet, other: Wallet
  let vault: GnoGenesisVault, keeper: Keeper, validatorsRegistry: Contract, gnoToken: ERC20Mock
  let poolEscrow: PoolEscrowMock
  let rewardToken: LegacyRewardTokenMock, depositDataManager: DepositDataManager

  let createGenesisVault: ThenArg<ReturnType<typeof gnoVaultFixture>>['createGnoGenesisVault']

  async function acceptPoolEscrowOwnership() {
    await vault.connect(admin).acceptPoolEscrowOwnership()
  }

  async function collatGnoVault() {
    await collateralizeGnoVault(
      vault,
      gnoToken,
      keeper,
      depositDataManager,
      admin,
      validatorsRegistry
    )
  }

  beforeEach('deploy fixtures', async () => {
    ;[admin, other] = await (ethers as any).getSigners()
    const fixture = await loadFixture(gnoVaultFixture)
    keeper = fixture.keeper
    validatorsRegistry = fixture.validatorsRegistry
    gnoToken = fixture.gnoToken
    depositDataManager = fixture.depositDataManager
    ;[vault, rewardToken, poolEscrow] = await fixture.createGnoGenesisVault(admin, {
      capacity,
      feePercent,
      metadataIpfsHash,
    })
    createGenesisVault = fixture.createGnoGenesisVault
  })

  it('initializes correctly', async () => {
    await expect(vault.connect(admin).initialize(ZERO_BYTES32)).to.revertedWithCustomError(
      vault,
      'InvalidInitialization'
    )
    expect(await vault.capacity()).to.be.eq(capacity)

    // VaultAdmin
    const adminAddr = await admin.getAddress()

    // VaultVersion
    expect(await vault.version()).to.be.eq(2)
    expect(await vault.vaultId()).to.be.eq(`0x${keccak256('GnoGenesisVault').toString('hex')}`)

    // VaultFee
    expect(await vault.admin()).to.be.eq(adminAddr)
    expect(await vault.feeRecipient()).to.be.eq(adminAddr)
  })

  it('has version', async () => {
    expect(await vault.version()).to.eq(2)
  })

  describe('migrate', () => {
    it('fails from not rewardToken', async () => {
      await expect(
        vault.connect(admin).migrate(await admin.getAddress(), ethers.parseEther('1'))
      ).to.be.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('fails when pool escrow ownership is not accepted', async () => {
      const [vault, rewardToken] = await createGenesisVault(admin, {
        capacity,
        feePercent,
        metadataIpfsHash,
      })
      const assets = ethers.parseEther('10')
      await expect(
        rewardToken.connect(other).migrate(other.address, assets, 0)
      ).to.be.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('fails with zero receiver', async () => {
      await acceptPoolEscrowOwnership()
      await collatGnoVault()
      const assets = ethers.parseEther('1')
      await expect(
        rewardToken.connect(other).migrate(ZERO_ADDRESS, assets, assets)
      ).to.be.revertedWithCustomError(vault, 'ZeroAddress')
    })

    it('fails with zero assets', async () => {
      await acceptPoolEscrowOwnership()
      await collatGnoVault()
      await expect(
        rewardToken.connect(other).migrate(other.address, 0, 0)
      ).to.be.revertedWithCustomError(vault, 'InvalidAssets')
    })

    it('fails when not collateralized', async () => {
      const [vault, rewardToken] = await createGenesisVault(admin, {
        capacity,
        feePercent,
        metadataIpfsHash,
      })
      await vault.connect(admin).acceptPoolEscrowOwnership()
      const assets = ethers.parseEther('1')
      await expect(
        rewardToken.connect(other).migrate(other.address, assets, assets)
      ).to.be.revertedWithCustomError(vault, 'NotCollateralized')
    })

    it('fails when not harvested', async () => {
      await acceptPoolEscrowOwnership()
      await collatGnoVault()
      const reward = ethers.parseEther('5')
      const unlockedMevReward = 0n
      const vaultAddr = await vault.getAddress()
      const vaultReward = getHarvestParams(vaultAddr, reward, unlockedMevReward)
      await updateRewards(keeper, [vaultReward])
      await updateRewards(keeper, [
        getHarvestParams(vaultAddr, reward + ethers.parseEther('5'), unlockedMevReward),
      ])

      const holder = other
      const assets = ethers.parseEther('1')
      await expect(
        rewardToken.connect(holder).migrate(await holder.getAddress(), assets, assets)
      ).to.be.revertedWithCustomError(vault, 'NotHarvested')
    })

    it('migrates from rewardToken', async () => {
      await acceptPoolEscrowOwnership()
      await collatGnoVault()
      const assets = ethers.parseEther('10')
      const expectedShares = await vault.convertToShares(assets)

      const holder = other
      const holderAddr = await holder.getAddress()

      const receipt = await rewardToken.connect(holder).migrate(holderAddr, assets, 0)
      expect(await vault.getShares(holderAddr)).to.eq(expectedShares)

      await expect(receipt).to.emit(vault, 'Migrated').withArgs(holderAddr, assets, expectedShares)
      await snapshotGasCost(receipt)
    })
  })

  it('pulls withdrawals on claim exited assets', async () => {
    await acceptPoolEscrowOwnership()
    const assets = ethers.parseEther('1') - SECURITY_DEPOSIT
    let tx = await depositGno(vault, gnoToken, assets, other, other, ZERO_ADDRESS)
    const shares = await extractDepositShares(tx)
    expect(await vault.getShares(other.address)).to.eq(shares)

    // register validator
    await registerEthValidator(vault, keeper, depositDataManager, admin, validatorsRegistry)
    expect(await gnoToken.balanceOf(await vault.getAddress())).to.eq(0n)

    // enter exit queue
    tx = await vault.connect(other).enterExitQueue(shares, other.address)
    const positionTicket = await extractExitPositionTicket(tx)
    const timestamp = await getBlockTimestamp(tx)
    expect(await vault.getExitQueueIndex(positionTicket)).to.eq(-1)

    // withdrawals arrives
    await setGnoWithdrawals(validatorsRegistry, gnoToken, poolEscrow, assets)
    const exitQueueIndex = await vault.getExitQueueIndex(positionTicket)
    expect(exitQueueIndex).to.eq(0)
    expect(await vault.withdrawableAssets()).to.eq(0n)

    // claim exited assets
    await increaseTime(EXITING_ASSETS_MIN_DELAY)
    tx = await vault.connect(other).claimExitedAssets(positionTicket, timestamp, exitQueueIndex)
    await expect(tx)
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(other.address, positionTicket, 0, assets)
    await snapshotGasCost(tx)
  })

  describe('update state', () => {
    let totalVaultAssets: bigint
    let totalLegacyAssets: bigint

    beforeEach(async () => {
      totalVaultAssets = ethers.parseEther('10')
      totalLegacyAssets = ethers.parseEther('5')
      await depositGno(
        vault,
        gnoToken,
        totalVaultAssets - SECURITY_DEPOSIT,
        other,
        other,
        ZERO_ADDRESS
      )
      await rewardToken.connect(other).setTotalStaked(totalLegacyAssets)
    })

    it('splits reward between rewardToken and vault', async () => {
      await acceptPoolEscrowOwnership()
      const reward = ethers.parseEther('30')
      const unlockedMevReward = 0n
      const expectedVaultDelta =
        (reward * totalVaultAssets) / (totalLegacyAssets + totalVaultAssets)
      const expectedLegacyDelta = reward - expectedVaultDelta
      const vaultReward = getHarvestParams(await vault.getAddress(), reward, unlockedMevReward)
      const rewardsTree = await updateRewards(keeper, [vaultReward])
      const proof = getRewardsRootProof(rewardsTree, vaultReward)
      const receipt = await vault.updateState({
        rewardsRoot: rewardsTree.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof,
      })

      expect(await rewardToken.totalAssets()).to.eq(totalLegacyAssets + expectedLegacyDelta)
      expect(await vault.totalAssets()).to.eq(totalVaultAssets + expectedVaultDelta)
      await snapshotGasCost(receipt)
    })

    it('skips updating legacy with zero total assets', async () => {
      await acceptPoolEscrowOwnership()
      await rewardToken.setTotalStaked(0n)
      await rewardToken.setTotalRewards(0n)
      await rewardToken.setTotalPenalty(0n)

      const reward = ethers.parseEther('5')
      const unlockedMevReward = 0n

      const vaultReward = getHarvestParams(await vault.getAddress(), reward, unlockedMevReward)
      const rewardsTree = await updateRewards(keeper, [vaultReward])
      const proof = getRewardsRootProof(rewardsTree, vaultReward)

      const totalLegacyAssetsBefore = await rewardToken.totalAssets()
      const totalVaultAssetsBefore = await vault.totalAssets()
      const receipt = await vault.updateState({
        rewardsRoot: rewardsTree.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof,
      })
      expect(await rewardToken.totalAssets()).to.eq(totalLegacyAssetsBefore)
      expect(await vault.totalAssets()).to.eq(totalVaultAssetsBefore + reward)
      await snapshotGasCost(receipt)
    })

    it('fails when pool escrow ownership not accepted', async () => {
      const [vault] = await createGenesisVault(admin, {
        capacity,
        feePercent,
        metadataIpfsHash,
      })
      const totalRewards = ethers.parseEther('30')
      const vaultReward = getHarvestParams(await vault.getAddress(), totalRewards, 0n)
      const rewardsTree = await updateRewards(keeper, [vaultReward])
      const proof = getRewardsRootProof(rewardsTree, vaultReward)
      await expect(
        vault.updateState({
          rewardsRoot: rewardsTree.root,
          reward: vaultReward.reward,
          unlockedMevReward: vaultReward.unlockedMevReward,
          proof,
        })
      ).to.be.revertedWithCustomError(vault, 'InvalidInitialHarvest')
    })

    it('fails with negative first update', async () => {
      const [vault] = await createGenesisVault(admin, {
        capacity,
        feePercent,
        metadataIpfsHash,
      })
      await vault.connect(admin).acceptPoolEscrowOwnership()
      const totalPenalty = ethers.parseEther('-5')
      const vaultReward = getHarvestParams(await vault.getAddress(), totalPenalty, 0n)
      const rewardsTree = await updateRewards(keeper, [vaultReward])
      const proof = getRewardsRootProof(rewardsTree, vaultReward)
      await expect(
        vault.updateState({
          rewardsRoot: rewardsTree.root,
          reward: vaultReward.reward,
          unlockedMevReward: vaultReward.unlockedMevReward,
          proof,
        })
      ).to.revertedWithCustomError(vault, 'InvalidInitialHarvest')
    })

    it('splits penalty between rewardToken and vault', async () => {
      await acceptPoolEscrowOwnership()
      await collatGnoVault()
      const reward = ethers.parseEther('-5')
      const unlockedMevReward = 0n
      const expectedVaultDelta =
        (reward * totalVaultAssets) / (totalLegacyAssets + totalVaultAssets)
      const expectedLegacyDelta = reward - expectedVaultDelta
      const vaultReward = getHarvestParams(await vault.getAddress(), reward, unlockedMevReward)
      const rewardsTree = await updateRewards(keeper, [vaultReward])
      const proof = getRewardsRootProof(rewardsTree, vaultReward)
      const receipt = await vault.updateState({
        rewardsRoot: rewardsTree.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof,
      })

      expect((await rewardToken.totalAssets()) - (await rewardToken.totalPenalty())).to.eq(
        totalLegacyAssets + expectedLegacyDelta + 1n // rounding error
      )
      expect(await vault.totalAssets()).to.eq(totalVaultAssets + expectedVaultDelta - 1n) // rounding error
      await snapshotGasCost(receipt)
    })

    it('deducts rewards on first state update', async () => {
      const [vault, rewardToken] = await createGenesisVault(admin, {
        capacity,
        feePercent,
        metadataIpfsHash,
      })
      await vault.connect(admin).acceptPoolEscrowOwnership()
      await depositGno(
        vault,
        gnoToken,
        totalVaultAssets - SECURITY_DEPOSIT,
        other,
        other,
        ZERO_ADDRESS
      )
      await rewardToken.connect(other).setTotalStaked(totalLegacyAssets)

      const totalRewards = ethers.parseEther('25')
      const legacyRewards = ethers.parseEther('5')
      await rewardToken.connect(other).setTotalRewards(legacyRewards)
      expect(await rewardToken.totalAssets()).to.eq(totalLegacyAssets + legacyRewards)
      expect(await rewardToken.totalRewards()).to.eq(legacyRewards)
      expect(await vault.totalAssets()).to.eq(totalVaultAssets)

      const expectedVaultDelta =
        ((totalRewards - legacyRewards) * totalVaultAssets) /
        (totalLegacyAssets + legacyRewards + totalVaultAssets)
      const expectedLegacyDelta = totalRewards - legacyRewards - expectedVaultDelta
      const vaultReward = getHarvestParams(await vault.getAddress(), totalRewards, 0n)
      const rewardsTree = await updateRewards(keeper, [vaultReward])
      const proof = getRewardsRootProof(rewardsTree, vaultReward)
      const receipt = await vault.updateState({
        rewardsRoot: rewardsTree.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof,
      })

      expect(await rewardToken.totalAssets()).to.eq(
        totalLegacyAssets + legacyRewards + expectedLegacyDelta
      )
      expect(await vault.totalAssets()).to.eq(totalVaultAssets + expectedVaultDelta)
      await snapshotGasCost(receipt)
    })
  })
})
