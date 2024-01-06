import hre, { ethers } from 'hardhat'
import { Contract, Signer, Wallet } from 'ethers'
import {
  EthGenesisVault,
  Keeper,
  PoolEscrowMock,
  RewardEthTokenMock,
  RewardEthTokenMock__factory,
  EthGenesisVault__factory,
  PoolEscrowMock__factory,
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
import { simulateDeployImpl } from '@openzeppelin/hardhat-upgrades/dist/utils'
import mainnetDeployment from '../deployments/mainnet.json'
import { MAINNET_FORK, NETWORKS } from '../helpers/constants'

describe('EthGenesisVault', () => {
  const capacity = ethers.parseEther('1000000')
  const feePercent = 500
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  const deadline = VALIDATORS_DEADLINE
  let dao: Wallet, admin: Signer, other: Wallet
  let vault: EthGenesisVault, keeper: Keeper, validatorsRegistry: Contract
  let poolEscrow: PoolEscrowMock
  let rewardEthToken: RewardEthTokenMock

  async function acceptPoolEscrowOwnership() {
    if (MAINNET_FORK.enabled) return
    await vault.connect(admin).acceptPoolEscrowOwnership()
  }

  async function collatEthVault() {
    if (MAINNET_FORK.enabled) return
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
  }

  beforeEach('deploy fixtures', async () => {
    ;[dao, admin, other] = await (ethers as any).getSigners()
    const fixture = await loadFixture(ethVaultFixture)
    keeper = fixture.keeper
    validatorsRegistry = fixture.validatorsRegistry

    if (MAINNET_FORK.enabled) {
      admin = await ethers.getImpersonatedSigner(NETWORKS.mainnet.genesisVault.admin)
      await setBalance(NETWORKS.mainnet.genesisVault.admin, ethers.parseEther('1'))
      vault = EthGenesisVault__factory.connect(mainnetDeployment.EthGenesisVault, admin)
      poolEscrow = PoolEscrowMock__factory.connect(NETWORKS.mainnet.genesisVault.poolEscrow, admin)
      rewardEthToken = RewardEthTokenMock__factory.connect(
        NETWORKS.mainnet.genesisVault.rewardEthToken,
        dao
      )
      return
    }

    let factory = await ethers.getContractFactory('RewardEthTokenMock')
    rewardEthToken = RewardEthTokenMock__factory.connect(
      await (await factory.deploy()).getAddress(),
      dao
    )
    poolEscrow = await createPoolEscrow(dao.address)
    factory = await ethers.getContractFactory('EthGenesisVault')
    const constructorArgs = [
      await fixture.keeper.getAddress(),
      await fixture.vaultsRegistry.getAddress(),
      await fixture.validatorsRegistry.getAddress(),
      await fixture.osToken.getAddress(),
      await fixture.osTokenConfig.getAddress(),
      await fixture.sharedMevEscrow.getAddress(),
      await poolEscrow.getAddress(),
      await rewardEthToken.getAddress(),
      EXITING_ASSETS_MIN_DELAY,
    ]
    const contract = await factory.deploy(...constructorArgs)
    const vaultImpl = await contract.getAddress()
    await simulateDeployImpl(hre, factory, { constructorArgs }, vaultImpl)
    const proxyFactory = await ethers.getContractFactory('ERC1967Proxy')
    const proxy = await proxyFactory.deploy(vaultImpl, '0x')
    const proxyAddress = await proxy.getAddress()

    // eslint-disable-next-line @typescript-eslint/ban-ts-comment
    // @ts-ignore
    vault = factory.attach(proxyAddress) as EthGenesisVault
    await rewardEthToken.setVault(await vault.getAddress())
    await poolEscrow.connect(dao).commitOwnershipTransfer(await vault.getAddress())
    const adminAddr = await admin.getAddress()
    const tx = await vault.initialize(
      ethers.AbiCoder.defaultAbiCoder().encode(
        ['address', 'tuple(uint256 capacity, uint16 feePercent, string metadataIpfsHash)'],
        [adminAddr, [capacity, feePercent, metadataIpfsHash]]
      ),
      { value: SECURITY_DEPOSIT }
    )
    await expect(tx).to.emit(vault, 'MetadataUpdated').withArgs(dao.address, metadataIpfsHash)
    await expect(tx).to.emit(vault, 'FeeRecipientUpdated').withArgs(dao.address, adminAddr)
    await expect(tx)
      .to.emit(vault, 'GenesisVaultCreated')
      .withArgs(adminAddr, capacity, feePercent, metadataIpfsHash)
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
    const adminAddr = await admin.getAddress()
    expect(await vault.admin()).to.be.eq(adminAddr)

    // VaultVersion
    expect(await vault.version()).to.be.eq(1)
    expect(await vault.vaultId()).to.be.eq(`0x${keccak256('EthGenesisVault').toString('hex')}`)

    // VaultFee
    if (!MAINNET_FORK.enabled) {
      expect(await vault.feeRecipient()).to.be.eq(adminAddr)
    }
    expect(await vault.feePercent()).to.be.eq(feePercent)
  })

  it('has version', async () => {
    expect(await vault.version()).to.eq(1)
  })

  it('applies ownership transfer', async () => {
    await acceptPoolEscrowOwnership()
    expect(await poolEscrow.owner()).to.eq(await vault.getAddress())
  })

  it('apply ownership cannot be called second time', async () => {
    await acceptPoolEscrowOwnership()
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
        vault.connect(admin).migrate(await admin.getAddress(), ethers.parseEther('1'))
      ).to.be.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('fails when pool escrow ownership is not accepted', async () => {
      if (MAINNET_FORK.enabled) return
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
      if (MAINNET_FORK.enabled) return
      await acceptPoolEscrowOwnership()
      const assets = ethers.parseEther('1')
      await expect(
        rewardEthToken.connect(other).migrate(other.address, assets, assets)
      ).to.be.revertedWithCustomError(vault, 'NotCollateralized')
    })

    it('fails when not harvested', async () => {
      await acceptPoolEscrowOwnership()
      await collatEthVault()
      let reward = ethers.parseEther('5')
      let unlockedMevReward = 0n
      if (MAINNET_FORK.enabled) {
        reward += MAINNET_FORK.genesisVaultHarvestParams.proofReward
        unlockedMevReward += MAINNET_FORK.genesisVaultHarvestParams.proofUnlockedMevReward
      }

      await updateRewards(keeper, [
        {
          reward,
          unlockedMevReward,
          vault: await vault.getAddress(),
        },
      ])
      reward += ethers.parseEther('5')
      await updateRewards(keeper, [
        {
          reward,
          unlockedMevReward,
          vault: await vault.getAddress(),
        },
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

  it('pulls assets on claim exited assets', async () => {
    await acceptPoolEscrowOwnership()
    await collatEthVault()

    const shares = ethers.parseEther('10')
    let assets = await vault.convertToAssets(shares)
    await vault.connect(other).deposit(other.address, ZERO_ADDRESS, { value: assets })

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
    let reward = 0n
    let unlockedMevReward = 0n
    if (MAINNET_FORK.enabled) {
      reward += MAINNET_FORK.genesisVaultHarvestParams.proofReward
      unlockedMevReward += MAINNET_FORK.genesisVaultHarvestParams.proofUnlockedMevReward
    }
    const tree = await updateRewards(keeper, [
      {
        reward,
        unlockedMevReward,
        vault: vaultAddr,
      },
    ])
    const proof = getRewardsRootProof(tree, {
      vault: vaultAddr,
      unlockedMevReward,
      reward,
    })
    await vault.updateState({
      rewardsRoot: tree.root,
      reward,
      unlockedMevReward,
      proof,
    })
    const exitQueueIndex = await vault.getExitQueueIndex(positionTicket)
    if (MAINNET_FORK.enabled) {
      assets -= 1n
    }

    const tx = await vault
      .connect(other)
      .claimExitedAssets(positionTicket, timestamp, exitQueueIndex)
    await expect(tx)
      .to.emit(poolEscrow, 'Withdrawn')
      .withArgs(vaultAddr, vaultAddr, poolEscrowBalance + vaultBalance)
    await expect(tx)
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(other.address, positionTicket, 0, assets)
    expect(await ethers.provider.getBalance(await poolEscrow.getAddress())).to.eq(0)
    await snapshotGasCost(tx)
  })

  it('pulls assets on redeem', async () => {
    if (MAINNET_FORK.enabled) return
    await acceptPoolEscrowOwnership()
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
    const tx = await registerEthValidator(vault, keeper, validatorsRegistry, admin)
    await expect(tx)
      .to.emit(poolEscrow, 'Withdrawn')
      .withArgs(vaultAddr, vaultAddr, validatorDeposit + vaultBalance + poolEscrowBalance)
    await snapshotGasCost(tx)
  })

  it('pulls assets on multiple validators registration', async () => {
    await acceptPoolEscrowOwnership()
    await collatEthVault()
    const validatorsData = await createEthValidatorsData(vault)
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

    if (MAINNET_FORK.enabled) {
      expectedShares += 1n
    }

    const receipt = await depositorMock.connect(other).depositToVault({ value: amount })
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
      let reward = ethers.parseEther('30')
      let unlockedMevReward = 0n
      const expectedVaultDelta =
        (reward * totalVaultAssets) / (totalLegacyAssets + totalVaultAssets)
      const expectedLegacyDelta = reward - expectedVaultDelta
      if (MAINNET_FORK.enabled) {
        reward += MAINNET_FORK.genesisVaultHarvestParams.proofReward
        unlockedMevReward += MAINNET_FORK.genesisVaultHarvestParams.proofUnlockedMevReward
      }
      const vaultReward = {
        reward,
        unlockedMevReward,
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

      if (MAINNET_FORK.enabled) {
        // rounding error
        totalLegacyAssets -= 1n
        totalVaultAssets += 1n
      }

      expect(await rewardEthToken.totalAssets()).to.eq(totalLegacyAssets + expectedLegacyDelta)
      expect(await vault.totalAssets()).to.eq(totalVaultAssets + expectedVaultDelta)
      await snapshotGasCost(receipt)
    })

    it('fails when pool escrow ownership not accepted', async () => {
      if (MAINNET_FORK.enabled) return
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
      if (MAINNET_FORK.enabled) return
      await acceptPoolEscrowOwnership()
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
      await acceptPoolEscrowOwnership()
      await collatEthVault()
      let reward = ethers.parseEther('-5')
      let unlockedMevReward = 0n
      const expectedVaultDelta =
        (reward * totalVaultAssets) / (totalLegacyAssets + totalVaultAssets)
      const expectedLegacyDelta = reward - expectedVaultDelta
      if (MAINNET_FORK.enabled) {
        reward += MAINNET_FORK.genesisVaultHarvestParams.proofReward
        unlockedMevReward += MAINNET_FORK.genesisVaultHarvestParams.proofUnlockedMevReward
      }
      const vaultReward = {
        reward,
        unlockedMevReward,
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
      if (MAINNET_FORK.enabled) return
      await acceptPoolEscrowOwnership()
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
