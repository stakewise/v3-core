import { ethers, upgrades, waffle } from 'hardhat'
import { BigNumber, Contract, Wallet } from 'ethers'
import { hexlify, parseEther } from 'ethers/lib/utils'
import { EthGenesisVault, Keeper, PoolEscrowMock, RewardEthTokenMock } from '../typechain-types'
import { createPoolEscrow, ethVaultFixture, getOraclesSignatures } from './shared/fixtures'
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

const createFixtureLoader = waffle.createFixtureLoader

describe('EthGenesisVault', () => {
  const capacity = parseEther('1000')
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  const deadline = VALIDATORS_DEADLINE
  let dao: Wallet, admin: Wallet, other: Wallet
  let vault: EthGenesisVault, keeper: Keeper, validatorsRegistry: Contract
  let poolEscrow: PoolEscrowMock
  let rewardEthToken: RewardEthTokenMock

  let loadFixture: ReturnType<typeof createFixtureLoader>

  before('create fixture loader', async () => {
    ;[dao, admin, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([dao])
  })

  beforeEach('deploy fixtures', async () => {
    const fixture = await loadFixture(ethVaultFixture)
    keeper = fixture.keeper
    validatorsRegistry = fixture.validatorsRegistry

    let factory = await ethers.getContractFactory('RewardEthTokenMock')
    rewardEthToken = (await factory.deploy()) as RewardEthTokenMock
    poolEscrow = await createPoolEscrow(dao.address)
    factory = await ethers.getContractFactory('EthGenesisVault')
    const proxy = await upgrades.deployProxy(factory, [], {
      unsafeAllow: ['delegatecall'],
      initializer: false,
      constructorArgs: [
        fixture.keeper.address,
        fixture.vaultsRegistry.address,
        fixture.validatorsRegistry.address,
        fixture.osToken.address,
        fixture.osTokenConfig.address,
        fixture.sharedMevEscrow.address,
        poolEscrow.address,
        rewardEthToken.address,
        EXITING_ASSETS_MIN_DELAY,
      ],
    })
    vault = (await proxy.deployed()) as EthGenesisVault
    await rewardEthToken.setVault(vault.address)
    await poolEscrow.connect(dao).commitOwnershipTransfer(vault.address)
    const tx = await vault.initialize(
      ethers.utils.defaultAbiCoder.encode(
        ['address', 'tuple(uint256 capacity, uint16 feePercent, string metadataIpfsHash)'],
        [admin.address, [capacity, feePercent, metadataIpfsHash]]
      ),
      { value: SECURITY_DEPOSIT }
    )
    await vault.connect(admin).acceptPoolEscrowOwnership()
    await expect(tx).to.emit(vault, 'MetadataUpdated').withArgs(dao.address, metadataIpfsHash)
    await expect(tx).to.emit(vault, 'FeeRecipientUpdated').withArgs(dao.address, admin.address)
    await expect(tx)
      .to.emit(vault, 'GenesisVaultCreated')
      .withArgs(admin.address, capacity, feePercent, metadataIpfsHash)
    expect(await vault.mevEscrow()).to.be.eq(fixture.sharedMevEscrow.address)

    await fixture.vaultsRegistry.connect(dao).addVault(vault.address)
  })

  it('initializes correctly', async () => {
    await expect(vault.connect(admin).initialize(ZERO_BYTES32)).to.revertedWith(
      'Initializable: contract is already initialized'
    )
    expect(await vault.capacity()).to.be.eq(capacity)

    // VaultAdmin
    expect(await vault.admin()).to.be.eq(admin.address)

    // VaultVersion
    expect(await vault.version()).to.be.eq(1)
    expect(await vault.vaultId()).to.be.eq(hexlify(keccak256('EthGenesisVault')))

    // VaultFee
    expect(await vault.feeRecipient()).to.be.eq(admin.address)
    expect(await vault.feePercent()).to.be.eq(feePercent)
  })

  it('has version', async () => {
    expect(await vault.version()).to.eq(1)
  })

  it('applies ownership transfer', async () => {
    expect(await poolEscrow.owner()).to.eq(vault.address)
  })

  it('apply ownership cannot be called second time', async () => {
    await expect(vault.connect(other).acceptPoolEscrowOwnership()).to.be.revertedWith(
      'AccessDenied'
    )
    await expect(vault.connect(admin).acceptPoolEscrowOwnership()).to.be.revertedWith(
      'PoolEscrow: caller is not the future owner'
    )
  })

  describe('migrate', () => {
    it('fails from not rewardEthToken', async () => {
      await expect(vault.connect(admin).migrate(admin.address, parseEther('1'))).to.be.revertedWith(
        'AccessDenied'
      )
    })

    it('fails with zero receiver', async () => {
      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
      const assets = parseEther('1')
      await expect(
        rewardEthToken.connect(other).migrate(ZERO_ADDRESS, assets, assets)
      ).to.be.revertedWith('ZeroAddress')
    })

    it('fails with zero assets', async () => {
      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
      await expect(rewardEthToken.connect(other).migrate(other.address, 0, 0)).to.be.revertedWith(
        'InvalidAssets'
      )
    })

    it('fails when not collateralized', async () => {
      const assets = parseEther('1')
      await expect(
        rewardEthToken.connect(other).migrate(other.address, assets, assets)
      ).to.be.revertedWith('NotCollateralized')
    })

    it('fails when not harvested', async () => {
      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
      await updateRewards(keeper, [
        {
          reward: parseEther('5'),
          unlockedMevReward: 0,
          vault: vault.address,
        },
      ])
      await updateRewards(keeper, [
        {
          reward: parseEther('10'),
          unlockedMevReward: 0,
          vault: vault.address,
        },
      ])
      const assets = parseEther('1')
      await expect(
        rewardEthToken.connect(other).migrate(other.address, assets, assets)
      ).to.be.revertedWith('NotHarvested')
    })

    it('migrates from rewardEthToken', async () => {
      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
      const assets = parseEther('10')
      const expectedShares = parseEther('10')
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
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)

    const shares = parseEther('10')
    await vault.connect(other).deposit(other.address, ZERO_ADDRESS, { value: shares })

    await setBalance(vault.address, BigNumber.from(0))
    const response = await vault.connect(other).enterExitQueue(shares, other.address)
    const receipt = await response.wait()
    const positionTicket = extractExitPositionTicket(receipt)
    const timestamp = await getBlockTimestamp(receipt)

    await setBalance(poolEscrow.address, shares)
    expect(await vault.withdrawableAssets()).to.eq(0)

    await increaseTime(ONE_DAY)
    const tree = await updateRewards(keeper, [
      {
        reward: 0,
        unlockedMevReward: 0,
        vault: vault.address,
      },
    ])
    const proof = getRewardsRootProof(tree, {
      vault: vault.address,
      unlockedMevReward: 0,
      reward: 0,
    })
    await vault.updateState({
      rewardsRoot: tree.root,
      reward: 0,
      unlockedMevReward: 0,
      proof,
    })
    const exitQueueIndex = await vault.getExitQueueIndex(positionTicket)

    const tx = await vault
      .connect(other)
      .claimExitedAssets(positionTicket, timestamp, exitQueueIndex)
    await expect(tx).to.emit(poolEscrow, 'Withdrawn').withArgs(vault.address, vault.address, shares)
    await expect(tx)
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(other.address, positionTicket, 0, shares)
    expect(await waffle.provider.getBalance(poolEscrow.address)).to.eq(0)
    await snapshotGasCost(tx)
  })

  it('pulls assets on redeem', async () => {
    const shares = parseEther('10')
    await vault.connect(other).deposit(other.address, ZERO_ADDRESS, { value: shares })

    await setBalance(vault.address, BigNumber.from(0))
    await setBalance(poolEscrow.address, shares)

    expect(await vault.withdrawableAssets()).to.eq(shares)

    const tx = await vault.connect(other).redeem(shares, other.address)
    await expect(tx)
      .to.emit(vault, 'Redeemed')
      .withArgs(other.address, other.address, shares, shares)
    await expect(tx).to.not.emit(vault, 'Deposited')
    await expect(tx).to.emit(poolEscrow, 'Withdrawn').withArgs(vault.address, vault.address, shares)
    expect(await waffle.provider.getBalance(poolEscrow.address)).to.eq(0)
  })

  it('pulls assets on single validator registration', async () => {
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
    const validatorDeposit = parseEther('32')
    await rewardEthToken.connect(other).migrate(other.address, validatorDeposit, validatorDeposit)
    await setBalance(vault.address, BigNumber.from(0))
    await setBalance(poolEscrow.address, validatorDeposit)
    expect(await vault.withdrawableAssets()).to.eq(validatorDeposit)
    const tx = await registerEthValidator(vault, keeper, validatorsRegistry, admin)
    await expect(tx)
      .to.emit(poolEscrow, 'Withdrawn')
      .withArgs(vault.address, vault.address, validatorDeposit)
    await snapshotGasCost(tx)
  })

  it('pulls assets on multiple validators registration', async () => {
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
    const validatorsData = await createEthValidatorsData(vault)
    const validatorsRegistryRoot = await validatorsRegistry.get_deposit_root()
    await vault.connect(admin).setValidatorsRoot(validatorsData.root)
    const proof = getValidatorsMultiProof(validatorsData.tree, validatorsData.validators, [
      ...Array(validatorsData.validators.length).keys(),
    ])
    const validators = validatorsData.validators
    const assets = parseEther('32').mul(validators.length)
    await rewardEthToken.connect(other).migrate(other.address, assets, assets)

    const sortedVals = proof.leaves.map((v) => v[0])
    const indexes = validators.map((v) => sortedVals.indexOf(v))
    await vault.connect(other).deposit(other.address, ZERO_ADDRESS, { value: assets })
    const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]

    const signingData = getEthValidatorsSigningData(
      Buffer.concat(validators),
      deadline,
      exitSignaturesIpfsHash,
      keeper,
      vault,
      validatorsRegistryRoot
    )
    const approveParams = {
      validatorsRegistryRoot,
      validators: hexlify(Buffer.concat(validators)),
      signatures: getOraclesSignatures(signingData, ORACLES.length),
      exitSignaturesIpfsHash,
      deadline,
    }

    await setBalance(vault.address, BigNumber.from(0))
    await setBalance(poolEscrow.address, assets)
    expect(await vault.withdrawableAssets()).to.eq(assets)

    const tx = await vault.registerValidators(approveParams, indexes, proof.proofFlags, proof.proof)
    await expect(tx).to.emit(poolEscrow, 'Withdrawn').withArgs(vault.address, vault.address, assets)
    await snapshotGasCost(tx)
  })

  it('can deposit through receive fallback function', async () => {
    const depositorMockFactory = await ethers.getContractFactory('DepositorMock')
    const depositorMock = await depositorMockFactory.deploy(vault.address)

    const amount = parseEther('100')
    const expectedShares = parseEther('100')
    expect(await vault.convertToShares(amount)).to.eq(expectedShares)

    const receipt = await depositorMock.connect(other).depositToVault({ value: amount })
    expect(await vault.getShares(depositorMock.address)).to.eq(expectedShares)

    await expect(receipt)
      .to.emit(vault, 'Deposited')
      .withArgs(depositorMock.address, depositorMock.address, amount, expectedShares, ZERO_ADDRESS)
    await snapshotGasCost(receipt)
  })

  describe('update state', () => {
    const totalVaultAssets: BigNumber = parseEther('10')
    const totalLegacyAssets: BigNumber = parseEther('5')

    beforeEach(async () => {
      await vault.deposit(other.address, ZERO_ADDRESS, {
        value: totalVaultAssets.sub(SECURITY_DEPOSIT),
      })

      await rewardEthToken.connect(other).setTotalStaked(totalLegacyAssets)
    })

    it('splits reward between rewardEthToken and vault', async () => {
      const totalRewards = parseEther('30')
      const expectedVaultDelta = totalRewards
        .mul(totalVaultAssets)
        .div(totalLegacyAssets.add(totalVaultAssets))
      const expectedLegacyDelta = totalRewards.sub(expectedVaultDelta)
      const vaultReward = {
        reward: totalRewards,
        unlockedMevReward: 0,
        vault: vault.address,
      }
      const rewardsTree = await updateRewards(keeper, [vaultReward])
      const proof = getRewardsRootProof(rewardsTree, vaultReward)
      const receipt = await vault.updateState({
        rewardsRoot: rewardsTree.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof,
      })

      expect(await rewardEthToken.totalAssets()).to.eq(totalLegacyAssets.add(expectedLegacyDelta))
      expect(await vault.totalAssets()).to.eq(totalVaultAssets.add(expectedVaultDelta))
      await snapshotGasCost(receipt)
    })

    it('fails with negative first update', async () => {
      const totalPenalty = parseEther('-5')
      const vaultReward = {
        reward: totalPenalty,
        unlockedMevReward: 0,
        vault: vault.address,
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
      ).to.revertedWith('NegativeAssetsDelta')
    })

    it('splits penalty between rewardEthToken and vault', async () => {
      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
      const totalPenalty = parseEther('-5')
      const expectedVaultDelta = totalPenalty
        .mul(totalVaultAssets)
        .div(totalLegacyAssets.add(totalVaultAssets))
      const expectedLegacyDelta = totalPenalty.sub(expectedVaultDelta)
      const vaultReward = {
        reward: totalPenalty,
        unlockedMevReward: 0,
        vault: vault.address,
      }
      const rewardsTree = await updateRewards(keeper, [vaultReward])
      const proof = getRewardsRootProof(rewardsTree, vaultReward)
      const receipt = await vault.updateState({
        rewardsRoot: rewardsTree.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof,
      })

      expect((await rewardEthToken.totalAssets()).sub(await rewardEthToken.totalPenalty())).to.eq(
        totalLegacyAssets.add(expectedLegacyDelta).add(1) // rounding error
      )
      expect(await vault.totalAssets()).to.eq(totalVaultAssets.add(expectedVaultDelta).sub(1)) // rounding error
      await snapshotGasCost(receipt)
    })

    it('deducts rewards on first state update', async () => {
      const totalRewards = parseEther('25')
      const legacyRewards = parseEther('5')
      await rewardEthToken.connect(other).setTotalRewards(legacyRewards)
      expect(await rewardEthToken.totalAssets()).to.eq(totalLegacyAssets.add(legacyRewards))
      expect(await rewardEthToken.totalRewards()).to.eq(legacyRewards)
      expect(await vault.totalAssets()).to.eq(totalVaultAssets)

      const expectedVaultDelta = totalRewards
        .sub(legacyRewards)
        .mul(totalVaultAssets)
        .div(totalLegacyAssets.add(legacyRewards).add(totalVaultAssets))
      const expectedLegacyDelta = totalRewards.sub(legacyRewards).sub(expectedVaultDelta)
      const vaultReward = {
        reward: totalRewards,
        unlockedMevReward: 0,
        vault: vault.address,
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
        totalLegacyAssets.add(legacyRewards).add(expectedLegacyDelta)
      )
      expect(await vault.totalAssets()).to.eq(totalVaultAssets.add(expectedVaultDelta))
      await snapshotGasCost(receipt)
    })
  })
})
