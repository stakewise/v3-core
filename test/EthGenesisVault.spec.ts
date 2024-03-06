import { ethers } from 'hardhat'
import { Contract, Signer, Wallet } from 'ethers'
import { EthGenesisVault, Keeper, PoolEscrowMock, LegacyRewardTokenMock } from '../typechain-types'
import { createDepositorMock, ethVaultFixture, getOraclesSignatures } from './shared/fixtures'
import { expect } from './shared/expect'
import keccak256 from 'keccak256'
import {
  ONE_DAY,
  ORACLES,
  SECURITY_DEPOSIT,
  VALIDATORS_DEADLINE,
  ZERO_ADDRESS,
  ZERO_BYTES32,
} from './shared/constants'
import snapshotGasCost from './shared/snapshotGasCost'
import {
  createEthValidatorsData,
  exitSignatureIpfsHashes,
  getEthValidatorsSigningData,
  getValidatorsMultiProof,
  registerEthValidator,
} from './shared/validators'
import {
  collateralizeEthVault,
  getHarvestParams,
  getRewardsRootProof,
  updateRewards,
} from './shared/rewards'
import {
  extractDepositShares,
  extractExitPositionTicket,
  getBlockTimestamp,
  increaseTime,
  setBalance,
} from './shared/utils'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { MAINNET_FORK } from '../helpers/constants'
import { ThenArg } from '../helpers/types'

describe('EthGenesisVault', () => {
  const capacity = ethers.parseEther('1000000')
  const feePercent = 500
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  const deadline = VALIDATORS_DEADLINE
  let admin: Signer, other: Wallet
  let vault: EthGenesisVault, keeper: Keeper, validatorsRegistry: Contract
  let poolEscrow: PoolEscrowMock
  let rewardEthToken: LegacyRewardTokenMock

  let createGenesisVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthGenesisVault']

  async function acceptPoolEscrowOwnership() {
    if (MAINNET_FORK.enabled) return
    await vault.connect(admin).acceptPoolEscrowOwnership()
  }

  async function collatEthVault() {
    if (MAINNET_FORK.enabled) return
    await collateralizeEthVault(
      vault,
      keeper,
      validatorsRegistry,
      admin,
      await poolEscrow.getAddress()
    )
  }

  beforeEach('deploy fixtures', async () => {
    ;[admin, other] = await (ethers as any).getSigners()
    const fixture = await loadFixture(ethVaultFixture)
    keeper = fixture.keeper
    validatorsRegistry = fixture.validatorsRegistry
    ;[vault, rewardEthToken, poolEscrow] = await fixture.createEthGenesisVault(admin, {
      capacity,
      feePercent,
      metadataIpfsHash,
    })
    admin = await ethers.getImpersonatedSigner(await vault.admin())
    createGenesisVault = fixture.createEthGenesisVault
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
    expect(await vault.vaultId()).to.be.eq(`0x${keccak256('EthGenesisVault').toString('hex')}`)

    // VaultFee
    if (!MAINNET_FORK.enabled) {
      expect(await vault.admin()).to.be.eq(adminAddr)
      expect(await vault.feeRecipient()).to.be.eq(adminAddr)
    }
    expect(await vault.feePercent()).to.be.eq(feePercent)
  })

  it('has version', async () => {
    expect(await vault.version()).to.eq(2)
  })

  describe('migrate', () => {
    it('fails from not rewardEthToken', async () => {
      await expect(
        vault.connect(admin).migrate(await admin.getAddress(), ethers.parseEther('1'))
      ).to.be.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('fails when pool escrow ownership is not accepted', async () => {
      const [vault, rewardEthToken] = await createGenesisVault(
        admin,
        {
          capacity,
          feePercent,
          metadataIpfsHash,
        },
        true
      )
      const assets = ethers.parseEther('10')
      await expect(
        rewardEthToken.connect(other).migrate(other.address, assets, 0)
      ).to.be.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('fails with zero receiver', async () => {
      await acceptPoolEscrowOwnership()
      await collatEthVault()
      const assets = ethers.parseEther('1')
      if (MAINNET_FORK.enabled) {
        await expect(
          rewardEthToken.connect(other).migrate(ZERO_ADDRESS, assets, assets)
        ).to.be.revertedWith('RewardEthToken: invalid receiver')
      } else {
        await expect(
          rewardEthToken.connect(other).migrate(ZERO_ADDRESS, assets, assets)
        ).to.be.revertedWithCustomError(vault, 'ZeroAddress')
      }
    })

    it('fails with zero assets', async () => {
      await acceptPoolEscrowOwnership()
      await collatEthVault()
      if (MAINNET_FORK.enabled) {
        await expect(rewardEthToken.connect(other).migrate(other.address, 0, 0)).to.be.revertedWith(
          'RewardEthToken: zero assets'
        )
      } else {
        await expect(
          rewardEthToken.connect(other).migrate(other.address, 0, 0)
        ).to.be.revertedWithCustomError(vault, 'InvalidAssets')
      }
    })

    it('fails when not collateralized', async () => {
      const [vault, rewardEthToken] = await createGenesisVault(
        admin,
        {
          capacity,
          feePercent,
          metadataIpfsHash,
        },
        true
      )
      await vault.connect(admin).acceptPoolEscrowOwnership()
      const assets = ethers.parseEther('1')
      await expect(
        rewardEthToken.connect(other).migrate(other.address, assets, assets)
      ).to.be.revertedWithCustomError(vault, 'NotCollateralized')
    })

    it('fails when not harvested', async () => {
      await acceptPoolEscrowOwnership()
      await collatEthVault()
      const reward = ethers.parseEther('5')
      const unlockedMevReward = 0n
      const vaultAddr = await vault.getAddress()
      const vaultReward = getHarvestParams(vaultAddr, reward, unlockedMevReward)
      await updateRewards(keeper, [vaultReward])
      await updateRewards(keeper, [
        getHarvestParams(vaultAddr, reward + ethers.parseEther('5'), unlockedMevReward),
      ])

      let holder: Signer
      if (MAINNET_FORK.enabled) {
        holder = await ethers.getImpersonatedSigner(MAINNET_FORK.v2PoolHolder)
      } else {
        holder = other
      }

      const assets = ethers.parseEther('1')
      await expect(
        rewardEthToken.connect(holder).migrate(await holder.getAddress(), assets, assets)
      ).to.be.revertedWithCustomError(vault, 'NotHarvested')
    })

    it('migrates from rewardEthToken', async () => {
      await acceptPoolEscrowOwnership()
      await collatEthVault()
      const assets = ethers.parseEther('10')
      const expectedShares = await vault.convertToShares(assets)

      let holder: Signer
      if (MAINNET_FORK.enabled) {
        holder = await ethers.getImpersonatedSigner(MAINNET_FORK.v2PoolHolder)
      } else {
        holder = other
      }
      const holderAddr = await holder.getAddress()

      const receipt = await rewardEthToken.connect(holder).migrate(holderAddr, assets, 0)
      expect(await vault.getShares(holderAddr)).to.eq(expectedShares)

      await expect(receipt).to.emit(vault, 'Migrated').withArgs(holderAddr, assets, expectedShares)
      await snapshotGasCost(receipt)
    })
  })

  it('pulls withdrawals on claim exited assets', async () => {
    await acceptPoolEscrowOwnership()
    await collatEthVault()

    const assets = ethers.parseEther('10')
    let tx = await vault.connect(other).deposit(other.address, ZERO_ADDRESS, { value: assets })
    const shares = await extractDepositShares(tx)

    const vaultAddr = await vault.getAddress()
    const vaultBalance = await ethers.provider.getBalance(vaultAddr)
    const poolEscrowAddr = await poolEscrow.getAddress()
    const poolEscrowBalance = await ethers.provider.getBalance(poolEscrowAddr)

    await setBalance(vaultAddr, 0n)
    const response = await vault.connect(other).enterExitQueue(shares, other.address)
    const positionTicket = await extractExitPositionTicket(response)
    const timestamp = await getBlockTimestamp(response)

    await setBalance(poolEscrowAddr, poolEscrowBalance + vaultBalance)

    await increaseTime(ONE_DAY)
    const reward = 0n
    const unlockedMevReward = 0n
    const harvestParams = getHarvestParams(vaultAddr, reward, unlockedMevReward)
    const tree = await updateRewards(keeper, [harvestParams])
    const proof = getRewardsRootProof(tree, harvestParams)
    await vault.updateState({
      rewardsRoot: tree.root,
      proof,
      reward: harvestParams.reward,
      unlockedMevReward: harvestParams.unlockedMevReward,
    })
    const exitQueueIndex = await vault.getExitQueueIndex(positionTicket)

    tx = await vault.connect(other).claimExitedAssets(positionTicket, timestamp, exitQueueIndex)
    await expect(tx)
      .to.emit(poolEscrow, 'Withdrawn')
      .withArgs(vaultAddr, vaultAddr, poolEscrowBalance + vaultBalance)
    await expect(tx)
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(other.address, positionTicket, 0, assets)
    expect(await ethers.provider.getBalance(await poolEscrow.getAddress())).to.eq(0)
    await snapshotGasCost(tx)
  })

  it('pulls withdrawals on single validator registration', async () => {
    await acceptPoolEscrowOwnership()
    await collatEthVault()
    const validatorDeposit = ethers.parseEther('32')
    const vaultAddr = await vault.getAddress()
    const vaultBalance = await ethers.provider.getBalance(vaultAddr)
    const poolEscrowAddr = await poolEscrow.getAddress()
    const poolEscrowBalance = await ethers.provider.getBalance(poolEscrowAddr)

    await setBalance(vaultAddr, 0n)
    await setBalance(poolEscrowAddr, validatorDeposit + vaultBalance + poolEscrowBalance)
    expect(await vault.withdrawableAssets()).to.be.greaterThanOrEqual(validatorDeposit)
    const tx = await registerEthValidator(vault, keeper, validatorsRegistry, admin, poolEscrowAddr)
    await expect(tx)
      .to.emit(poolEscrow, 'Withdrawn')
      .withArgs(vaultAddr, vaultAddr, validatorDeposit + vaultBalance + poolEscrowBalance)
    await snapshotGasCost(tx)
  })

  it('pulls withdrawals on multiple validators registration', async () => {
    await acceptPoolEscrowOwnership()
    await collatEthVault()
    const validatorsData = await createEthValidatorsData(vault, await poolEscrow.getAddress())
    const validatorsRegistryRoot = await validatorsRegistry.get_deposit_root()
    await vault.connect(admin).setValidatorsRoot(validatorsData.root)
    const proof = getValidatorsMultiProof(validatorsData.tree, validatorsData.validators, [
      ...Array(validatorsData.validators.length).keys(),
    ])
    const validators = validatorsData.validators
    const assets = ethers.parseEther('32') * BigInt(validators.length)

    const sortedVals = proof.leaves.map((v) => v[0])
    const indexes = validators.map((v) => sortedVals.indexOf(v))
    await vault.connect(other).deposit(other.address, ZERO_ADDRESS, { value: assets })
    const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]

    const signingData = await getEthValidatorsSigningData(
      Buffer.concat(validators),
      deadline,
      exitSignaturesIpfsHash,
      keeper,
      vault,
      validatorsRegistryRoot
    )
    const approveParams = {
      validatorsRegistryRoot,
      validators: `0x${Buffer.concat(validators).toString('hex')}`,
      signatures: getOraclesSignatures(signingData, ORACLES.length),
      exitSignaturesIpfsHash,
      deadline,
    }

    const vaultAddr = await vault.getAddress()
    const vaultBalance = await ethers.provider.getBalance(vaultAddr)
    const poolEscrowAddr = await poolEscrow.getAddress()
    const poolEscrowBalance = await ethers.provider.getBalance(poolEscrowAddr)

    await setBalance(vaultAddr, 0n)
    await setBalance(poolEscrowAddr, assets + vaultBalance + poolEscrowBalance)

    const tx = await vault.registerValidators(approveParams, indexes, proof.proofFlags, proof.proof)
    await expect(tx)
      .to.emit(poolEscrow, 'Withdrawn')
      .withArgs(vaultAddr, vaultAddr, assets + vaultBalance + poolEscrowBalance)
    await snapshotGasCost(tx)
  })

  it('can deposit through receive fallback function', async () => {
    const depositorMock = await createDepositorMock(vault)
    const depositorMockAddr = await depositorMock.getAddress()
    const amount = ethers.parseEther('100')
    let expectedShares = await vault.convertToShares(amount)

    const receipt = await depositorMock.connect(other).depositToVault({ value: amount })
    if (MAINNET_FORK.enabled) {
      expectedShares += 1n // rounding error
    }
    expect(await vault.getShares(await depositorMock.getAddress())).to.eq(expectedShares)

    await expect(receipt)
      .to.emit(vault, 'Deposited')
      .withArgs(depositorMockAddr, depositorMockAddr, amount, expectedShares, ZERO_ADDRESS)
    await snapshotGasCost(receipt)
  })

  describe('update state', () => {
    let totalVaultAssets: bigint
    let totalLegacyAssets: bigint

    beforeEach(async () => {
      if (MAINNET_FORK.enabled) {
        totalVaultAssets = await vault.totalAssets()
        totalLegacyAssets = await rewardEthToken.totalAssets()
      } else {
        totalVaultAssets = ethers.parseEther('10')
        totalLegacyAssets = ethers.parseEther('5')
        await vault.deposit(other.address, ZERO_ADDRESS, {
          value: totalVaultAssets - SECURITY_DEPOSIT,
        })
        await rewardEthToken.connect(other).setTotalStaked(totalLegacyAssets)
      }
    })

    it('splits reward between rewardEthToken and vault', async () => {
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

      if (MAINNET_FORK.enabled) {
        // rounding error
        totalLegacyAssets -= 1n
        totalVaultAssets += 1n
      }

      expect(await rewardEthToken.totalAssets()).to.eq(totalLegacyAssets + expectedLegacyDelta)
      expect(await vault.totalAssets()).to.eq(totalVaultAssets + expectedVaultDelta)
      await snapshotGasCost(receipt)
    })

    it('skips updating legacy with zero total assets', async () => {
      if (MAINNET_FORK.enabled) return
      await acceptPoolEscrowOwnership()
      await rewardEthToken.setTotalStaked(0n)
      await rewardEthToken.setTotalRewards(0n)
      await rewardEthToken.setTotalPenalty(0n)

      const reward = ethers.parseEther('5')
      const unlockedMevReward = 0n

      const vaultReward = getHarvestParams(await vault.getAddress(), reward, unlockedMevReward)
      const rewardsTree = await updateRewards(keeper, [vaultReward])
      const proof = getRewardsRootProof(rewardsTree, vaultReward)

      const totalLegacyAssetsBefore = await rewardEthToken.totalAssets()
      const totalVaultAssetsBefore = await vault.totalAssets()
      const receipt = await vault.updateState({
        rewardsRoot: rewardsTree.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof,
      })
      expect(await rewardEthToken.totalAssets()).to.eq(totalLegacyAssetsBefore)
      expect(await vault.totalAssets()).to.eq(totalVaultAssetsBefore + reward)
      await snapshotGasCost(receipt)
    })

    it('fails when pool escrow ownership not accepted', async () => {
      const [vault] = await createGenesisVault(
        admin,
        {
          capacity,
          feePercent,
          metadataIpfsHash,
        },
        true
      )
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
      const [vault] = await createGenesisVault(
        admin,
        {
          capacity,
          feePercent,
          metadataIpfsHash,
        },
        true
      )
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

    it('splits penalty between rewardEthToken and vault', async () => {
      await acceptPoolEscrowOwnership()
      await collatEthVault()
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

      expect((await rewardEthToken.totalAssets()) - (await rewardEthToken.totalPenalty())).to.eq(
        totalLegacyAssets + expectedLegacyDelta + 1n // rounding error
      )
      expect(await vault.totalAssets()).to.eq(totalVaultAssets + expectedVaultDelta - 1n) // rounding error
      await snapshotGasCost(receipt)
    })

    it('deducts rewards on first state update', async () => {
      const [vault, rewardEthToken] = await createGenesisVault(
        admin,
        {
          capacity,
          feePercent,
          metadataIpfsHash,
        },
        true
      )
      await vault.connect(admin).acceptPoolEscrowOwnership()
      await vault.deposit(other.address, ZERO_ADDRESS, {
        value: totalVaultAssets - SECURITY_DEPOSIT,
      })
      await rewardEthToken.connect(other).setTotalStaked(totalLegacyAssets)

      const totalRewards = ethers.parseEther('25')
      const legacyRewards = ethers.parseEther('5')
      await rewardEthToken.connect(other).setTotalRewards(legacyRewards)
      expect(await rewardEthToken.totalAssets()).to.eq(totalLegacyAssets + legacyRewards)
      expect(await rewardEthToken.totalRewards()).to.eq(legacyRewards)
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

      if (MAINNET_FORK.enabled) {
        // rounding error
        totalLegacyAssets -= 1n
        totalVaultAssets += 1n
      }

      expect(await rewardEthToken.totalAssets()).to.eq(
        totalLegacyAssets + legacyRewards + expectedLegacyDelta
      )
      expect(await vault.totalAssets()).to.eq(totalVaultAssets + expectedVaultDelta)
      await snapshotGasCost(receipt)
    })
  })
})
