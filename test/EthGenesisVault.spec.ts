import { ethers, upgrades } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import {
  EthGenesisVault,
  EthGenesisVault__factory,
  Keeper,
  PoolEscrowMock,
  RewardEthTokenMock,
  RewardEthTokenMock__factory,
} from '../typechain-types'
import {
  createDepositorMock,
  createPoolEscrow,
  ethVaultFixture,
  getOraclesSignatures,
} from './shared/fixtures'
import { expect } from './shared/expect'
import keccak256 from 'keccak256'
import {
  EXITING_ASSETS_MIN_DELAY,
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
import { collateralizeEthVault, getRewardsRootProof, updateRewards } from './shared/rewards'
import {
  extractExitPositionTicket,
  getBlockTimestamp,
  increaseTime,
  setBalance,
} from './shared/utils'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'

describe('EthGenesisVault', () => {
  const capacity = ethers.parseEther('1000')
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  const deadline = VALIDATORS_DEADLINE
  let dao: Wallet, admin: Wallet, other: Wallet
  let vault: EthGenesisVault, keeper: Keeper, validatorsRegistry: Contract
  let poolEscrow: PoolEscrowMock
  let rewardEthToken: RewardEthTokenMock

  beforeEach('deploy fixtures', async () => {
    ;[dao, admin, other] = await (ethers as any).getSigners()
    const fixture = await loadFixture(ethVaultFixture)
    keeper = fixture.keeper
    validatorsRegistry = fixture.validatorsRegistry

    let factory = await ethers.getContractFactory('RewardEthTokenMock')
    rewardEthToken = RewardEthTokenMock__factory.connect(
      await (await factory.deploy()).getAddress(),
      dao
    )
    poolEscrow = await createPoolEscrow(dao.address)
    factory = await ethers.getContractFactory('EthGenesisVault')
    const proxy = await upgrades.deployProxy(factory, [], {
      unsafeAllow: ['delegatecall'],
      initializer: false,
      constructorArgs: [
        await fixture.keeper.getAddress(),
        await fixture.vaultsRegistry.getAddress(),
        await fixture.validatorsRegistry.getAddress(),
        await fixture.osToken.getAddress(),
        await fixture.osTokenConfig.getAddress(),
        await fixture.sharedMevEscrow.getAddress(),
        await poolEscrow.getAddress(),
        await rewardEthToken.getAddress(),
        EXITING_ASSETS_MIN_DELAY,
      ],
    })
    vault = EthGenesisVault__factory.connect(await proxy.getAddress(), dao)
    await rewardEthToken.setVault(await vault.getAddress())
    await poolEscrow.connect(dao).commitOwnershipTransfer(await vault.getAddress())
    const tx = await vault.initialize(
      ethers.AbiCoder.defaultAbiCoder().encode(
        ['address', 'tuple(uint256 capacity, uint16 feePercent, string metadataIpfsHash)'],
        [admin.address, [capacity, feePercent, metadataIpfsHash]]
      ),
      { value: SECURITY_DEPOSIT }
    )
    await expect(tx).to.emit(vault, 'MetadataUpdated').withArgs(dao.address, metadataIpfsHash)
    await expect(tx).to.emit(vault, 'FeeRecipientUpdated').withArgs(dao.address, admin.address)
    await expect(tx)
      .to.emit(vault, 'GenesisVaultCreated')
      .withArgs(admin.address, capacity, feePercent, metadataIpfsHash)
    expect(await vault.mevEscrow()).to.be.eq(await fixture.sharedMevEscrow.getAddress())

    await fixture.vaultsRegistry.connect(dao).addVault(await vault.getAddress())
  })

  it('initializes correctly', async () => {
    await expect(vault.connect(admin).initialize(ZERO_BYTES32)).to.revertedWithCustomError(
      vault,
      'InvalidInitialization'
    )
    expect(await vault.capacity()).to.be.eq(capacity)

    // VaultAdmin
    expect(await vault.admin()).to.be.eq(admin.address)

    // VaultVersion
    expect(await vault.version()).to.be.eq(1)
    expect(await vault.vaultId()).to.be.eq(`0x${keccak256('EthGenesisVault').toString('hex')}`)

    // VaultFee
    expect(await vault.feeRecipient()).to.be.eq(admin.address)
    expect(await vault.feePercent()).to.be.eq(feePercent)
  })

  it('has version', async () => {
    expect(await vault.version()).to.eq(1)
  })

  it('applies ownership transfer', async () => {
    await vault.connect(admin).acceptPoolEscrowOwnership()
    expect(await poolEscrow.owner()).to.eq(await vault.getAddress())
  })

  it('apply ownership cannot be called second time', async () => {
    await vault.connect(admin).acceptPoolEscrowOwnership()
    await expect(vault.connect(other).acceptPoolEscrowOwnership()).to.be.revertedWithCustomError(
      vault,
      'AccessDenied'
    )
    await expect(vault.connect(admin).acceptPoolEscrowOwnership()).to.be.revertedWith(
      'PoolEscrow: caller is not the future owner'
    )
  })

  describe('migrate', () => {
    it('fails from not rewardEthToken', async () => {
      await expect(
        vault.connect(admin).migrate(admin.address, ethers.parseEther('1'))
      ).to.be.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('fails when pool escrow ownership is not accepted', async () => {
      const assets = ethers.parseEther('10')
      await expect(
        rewardEthToken.connect(other).migrate(other.address, assets, 0)
      ).to.be.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('fails with zero receiver', async () => {
      await vault.connect(admin).acceptPoolEscrowOwnership()
      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
      const assets = ethers.parseEther('1')
      await expect(
        rewardEthToken.connect(other).migrate(ZERO_ADDRESS, assets, assets)
      ).to.be.revertedWithCustomError(vault, 'ZeroAddress')
    })

    it('fails with zero assets', async () => {
      await vault.connect(admin).acceptPoolEscrowOwnership()
      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
      await expect(
        rewardEthToken.connect(other).migrate(other.address, 0, 0)
      ).to.be.revertedWithCustomError(vault, 'InvalidAssets')
    })

    it('fails when not collateralized', async () => {
      await vault.connect(admin).acceptPoolEscrowOwnership()
      const assets = ethers.parseEther('1')
      await expect(
        rewardEthToken.connect(other).migrate(other.address, assets, assets)
      ).to.be.revertedWithCustomError(vault, 'NotCollateralized')
    })

    it('fails when not harvested', async () => {
      await vault.connect(admin).acceptPoolEscrowOwnership()
      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
      await updateRewards(keeper, [
        {
          reward: ethers.parseEther('5'),
          unlockedMevReward: 0n,
          vault: await vault.getAddress(),
        },
      ])
      await updateRewards(keeper, [
        {
          reward: ethers.parseEther('10'),
          unlockedMevReward: 0n,
          vault: await vault.getAddress(),
        },
      ])
      const assets = ethers.parseEther('1')
      await expect(
        rewardEthToken.connect(other).migrate(other.address, assets, assets)
      ).to.be.revertedWithCustomError(vault, 'NotHarvested')
    })

    it('migrates from rewardEthToken', async () => {
      await vault.connect(admin).acceptPoolEscrowOwnership()
      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
      const assets = ethers.parseEther('10')
      const expectedShares = ethers.parseEther('10')
      expect(await vault.convertToShares(assets)).to.eq(expectedShares)

      const receipt = await rewardEthToken.connect(other).migrate(other.address, assets, 0)
      expect(await vault.getShares(other.address)).to.eq(expectedShares)

      await expect(receipt)
        .to.emit(vault, 'Migrated')
        .withArgs(other.address, assets, expectedShares)
      await snapshotGasCost(receipt)
    })
  })

  it('pulls assets on claim exited assets', async () => {
    await vault.connect(admin).acceptPoolEscrowOwnership()
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)

    const shares = ethers.parseEther('10')
    await vault.connect(other).deposit(other.address, ZERO_ADDRESS, { value: shares })

    await setBalance(await vault.getAddress(), 0n)
    const response = await vault.connect(other).enterExitQueue(shares, other.address)
    const positionTicket = await extractExitPositionTicket(response)
    const timestamp = await getBlockTimestamp(response)

    await setBalance(await poolEscrow.getAddress(), shares)
    expect(await vault.withdrawableAssets()).to.eq(0)

    await increaseTime(ONE_DAY)
    const tree = await updateRewards(keeper, [
      {
        reward: 0n,
        unlockedMevReward: 0n,
        vault: await vault.getAddress(),
      },
    ])
    const proof = getRewardsRootProof(tree, {
      vault: await vault.getAddress(),
      unlockedMevReward: 0n,
      reward: 0n,
    })
    await vault.updateState({
      rewardsRoot: tree.root,
      reward: 0n,
      unlockedMevReward: 0n,
      proof,
    })
    const exitQueueIndex = await vault.getExitQueueIndex(positionTicket)

    const tx = await vault
      .connect(other)
      .claimExitedAssets(positionTicket, timestamp, exitQueueIndex)
    await expect(tx)
      .to.emit(poolEscrow, 'Withdrawn')
      .withArgs(await vault.getAddress(), await vault.getAddress(), shares)
    await expect(tx)
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(other.address, positionTicket, 0, shares)
    expect(await ethers.provider.getBalance(await poolEscrow.getAddress())).to.eq(0)
    await snapshotGasCost(tx)
  })

  it('pulls assets on redeem', async () => {
    await vault.connect(admin).acceptPoolEscrowOwnership()
    const shares = ethers.parseEther('10')
    await vault.connect(other).deposit(other.address, ZERO_ADDRESS, { value: shares })

    await setBalance(await vault.getAddress(), 0n)
    await setBalance(await poolEscrow.getAddress(), shares)

    expect(await vault.withdrawableAssets()).to.eq(shares)

    const tx = await vault.connect(other).redeem(shares, other.address)
    await expect(tx)
      .to.emit(vault, 'Redeemed')
      .withArgs(other.address, other.address, shares, shares)
    await expect(tx).to.not.emit(vault, 'Deposited')
    await expect(tx)
      .to.emit(poolEscrow, 'Withdrawn')
      .withArgs(await vault.getAddress(), await vault.getAddress(), shares)
    expect(await ethers.provider.getBalance(await poolEscrow.getAddress())).to.eq(0)
  })

  it('pulls assets on single validator registration', async () => {
    await vault.connect(admin).acceptPoolEscrowOwnership()
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
    const validatorDeposit = ethers.parseEther('32')
    await rewardEthToken.connect(other).migrate(other.address, validatorDeposit, validatorDeposit)
    await setBalance(await vault.getAddress(), 0n)
    await setBalance(await poolEscrow.getAddress(), validatorDeposit)
    expect(await vault.withdrawableAssets()).to.eq(validatorDeposit)
    const tx = await registerEthValidator(vault, keeper, validatorsRegistry, admin)
    await expect(tx)
      .to.emit(poolEscrow, 'Withdrawn')
      .withArgs(await vault.getAddress(), await vault.getAddress(), validatorDeposit)
    await snapshotGasCost(tx)
  })

  it('pulls assets on multiple validators registration', async () => {
    await vault.connect(admin).acceptPoolEscrowOwnership()
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
    const validatorsData = await createEthValidatorsData(vault)
    const validatorsRegistryRoot = await validatorsRegistry.get_deposit_root()
    await vault.connect(admin).setValidatorsRoot(validatorsData.root)
    const proof = getValidatorsMultiProof(validatorsData.tree, validatorsData.validators, [
      ...Array(validatorsData.validators.length).keys(),
    ])
    const validators = validatorsData.validators
    const assets = ethers.parseEther('32') * BigInt(validators.length)
    await rewardEthToken.connect(other).migrate(other.address, assets, assets)

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

    await setBalance(await vault.getAddress(), 0n)
    await setBalance(await poolEscrow.getAddress(), assets)
    expect(await vault.withdrawableAssets()).to.eq(assets)

    const tx = await vault.registerValidators(approveParams, indexes, proof.proofFlags, proof.proof)
    await expect(tx)
      .to.emit(poolEscrow, 'Withdrawn')
      .withArgs(await vault.getAddress(), await vault.getAddress(), assets)
    await snapshotGasCost(tx)
  })

  it('can deposit through receive fallback function', async () => {
    const depositorMock = await createDepositorMock(vault)
    const amount = ethers.parseEther('100')
    const expectedShares = ethers.parseEther('100')
    expect(await vault.convertToShares(amount)).to.eq(expectedShares)

    const receipt = await depositorMock.connect(other).depositToVault({ value: amount })
    expect(await vault.getShares(await depositorMock.getAddress())).to.eq(expectedShares)

    await expect(receipt)
      .to.emit(vault, 'Deposited')
      .withArgs(
        await depositorMock.getAddress(),
        await depositorMock.getAddress(),
        amount,
        expectedShares,
        ZERO_ADDRESS
      )
    await snapshotGasCost(receipt)
  })

  describe('update state', () => {
    const totalVaultAssets: bigint = ethers.parseEther('10')
    const totalLegacyAssets: bigint = ethers.parseEther('5')

    beforeEach(async () => {
      await vault.deposit(other.address, ZERO_ADDRESS, {
        value: totalVaultAssets - SECURITY_DEPOSIT,
      })

      await rewardEthToken.connect(other).setTotalStaked(totalLegacyAssets)
    })

    it('splits reward between rewardEthToken and vault', async () => {
      await vault.connect(admin).acceptPoolEscrowOwnership()
      const totalRewards = ethers.parseEther('30')
      const expectedVaultDelta =
        (totalRewards * totalVaultAssets) / (totalLegacyAssets + totalVaultAssets)
      const expectedLegacyDelta = totalRewards - expectedVaultDelta
      const vaultReward = {
        reward: totalRewards,
        unlockedMevReward: 0n,
        vault: await vault.getAddress(),
      }
      const rewardsTree = await updateRewards(keeper, [vaultReward])
      const proof = getRewardsRootProof(rewardsTree, vaultReward)
      const receipt = await vault.updateState({
        rewardsRoot: rewardsTree.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof,
      })

      expect(await rewardEthToken.totalAssets()).to.eq(totalLegacyAssets + expectedLegacyDelta)
      expect(await vault.totalAssets()).to.eq(totalVaultAssets + expectedVaultDelta)
      await snapshotGasCost(receipt)
    })

    it('fails when pool escrow ownership not accepted', async () => {
      const totalRewards = ethers.parseEther('30')
      const vaultReward = {
        reward: totalRewards,
        unlockedMevReward: 0n,
        vault: await vault.getAddress(),
      }
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
      await vault.connect(admin).acceptPoolEscrowOwnership()
      const totalPenalty = ethers.parseEther('-5')
      const vaultReward = {
        reward: totalPenalty,
        unlockedMevReward: 0n,
        vault: await vault.getAddress(),
      }
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
      await vault.connect(admin).acceptPoolEscrowOwnership()
      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
      const totalPenalty = ethers.parseEther('-5')
      const expectedVaultDelta =
        (totalPenalty * totalVaultAssets) / (totalLegacyAssets + totalVaultAssets)
      const expectedLegacyDelta = totalPenalty - expectedVaultDelta
      const vaultReward = {
        reward: totalPenalty,
        unlockedMevReward: 0n,
        vault: await vault.getAddress(),
      }
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
      await vault.connect(admin).acceptPoolEscrowOwnership()
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
      const vaultReward = {
        reward: totalRewards,
        unlockedMevReward: 0n,
        vault: await vault.getAddress(),
      }
      const rewardsTree = await updateRewards(keeper, [vaultReward])
      const proof = getRewardsRootProof(rewardsTree, vaultReward)
      const receipt = await vault.updateState({
        rewardsRoot: rewardsTree.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof,
      })

      expect(await rewardEthToken.totalAssets()).to.eq(
        totalLegacyAssets + legacyRewards + expectedLegacyDelta
      )
      expect(await vault.totalAssets()).to.eq(totalVaultAssets + expectedVaultDelta)
      await snapshotGasCost(receipt)
    })
  })
})
