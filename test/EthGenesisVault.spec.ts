import { ethers, upgrades, waffle } from 'hardhat'
import { BigNumber, Contract, Wallet } from 'ethers'
import { hexlify, parseEther } from 'ethers/lib/utils'
import { EthGenesisVault, PoolEscrowMock, Keeper } from '../typechain-types'
import { createPoolEscrow, ethVaultFixture, getOraclesSignatures } from './shared/fixtures'
import { expect } from './shared/expect'
import keccak256 from 'keccak256'
import { ONE_DAY, ORACLES, SECURITY_DEPOSIT, ZERO_ADDRESS, ZERO_BYTES32 } from './shared/constants'
import snapshotGasCost from './shared/snapshotGasCost'
import {
  createEthValidatorsData,
  exitSignatureIpfsHashes,
  getEthValidatorsSigningData,
  getValidatorsMultiProof,
  registerEthValidator,
} from './shared/validators'
import { collateralizeEthVault, updateRewards } from './shared/rewards'
import { increaseTime, setBalance } from './shared/utils'

const createFixtureLoader = waffle.createFixtureLoader

describe('EthGenesisVault', () => {
  const capacity = parseEther('1000')
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  let dao: Wallet, admin: Wallet, stakedEthToken: Wallet, other: Wallet
  let vault: EthGenesisVault, keeper: Keeper, validatorsRegistry: Contract
  let poolEscrow: PoolEscrowMock

  let loadFixture: ReturnType<typeof createFixtureLoader>

  before('create fixture loader', async () => {
    ;[dao, admin, stakedEthToken, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([dao])
  })

  beforeEach('deploy fixtures', async () => {
    const fixture = await loadFixture(ethVaultFixture)
    keeper = fixture.keeper
    validatorsRegistry = fixture.validatorsRegistry

    poolEscrow = await createPoolEscrow(stakedEthToken.address)
    const factory = await ethers.getContractFactory('EthGenesisVault')
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
        stakedEthToken.address,
      ],
    })
    vault = (await proxy.deployed()) as EthGenesisVault
    await poolEscrow.connect(stakedEthToken).commitOwnershipTransfer(vault.address)
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
    expect(await vault.mevEscrow()).to.be.eq(fixture.sharedMevEscrow.address)

    await fixture.vaultsRegistry.connect(dao).addVault(vault.address)
    await fixture.osToken.connect(dao).setVaultImplementation(await vault.implementation(), true)
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
    it('fails from not stakedEthToken', async () => {
      await expect(vault.connect(admin).migrate(admin.address, parseEther('1'))).to.be.revertedWith(
        'AccessDenied'
      )
    })

    it('fails with zero receiver', async () => {
      await expect(
        vault.connect(stakedEthToken).migrate(ZERO_ADDRESS, parseEther('1'))
      ).to.be.revertedWith('ZeroAddress')
    })

    it('fails with zero assets', async () => {
      await expect(vault.connect(stakedEthToken).migrate(admin.address, 0)).to.be.revertedWith(
        'InvalidAssets'
      )
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
      await expect(
        vault.connect(stakedEthToken).migrate(other.address, parseEther('1'))
      ).to.be.revertedWith('NotHarvested')
    })

    it('migrates from stakedEthToken', async () => {
      const assets = parseEther('10')
      const expectedShares = parseEther('10')
      expect(await vault.convertToShares(assets)).to.eq(expectedShares)

      const receipt = await vault.connect(stakedEthToken).migrate(other.address, assets)
      expect(await vault.balanceOf(other.address)).to.eq(expectedShares)

      await expect(receipt)
        .to.emit(vault, 'Migrated')
        .withArgs(other.address, assets, expectedShares)
      await snapshotGasCost(receipt)
    })
  })

  it('pulls assets on claim exited assets', async () => {
    const data = await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
    const harvestData = { rewardsRoot: data[0], reward: 0, unlockedMevReward: 0, proof: data[1] }

    const shares = parseEther('10')
    await vault.connect(other).deposit(other.address, ZERO_ADDRESS, { value: shares })

    await setBalance(vault.address, BigNumber.from(0))
    const positionTicket = await vault
      .connect(other)
      .callStatic.enterExitQueue(shares, other.address)
    await vault.connect(other).enterExitQueue(shares, other.address)

    await setBalance(poolEscrow.address, shares)
    expect(await vault.withdrawableAssets()).to.eq(0)

    await increaseTime(ONE_DAY)
    await vault.updateState(harvestData)
    const exitQueueIndex = await vault.getExitQueueIndex(positionTicket)

    const tx = await vault.connect(other).claimExitedAssets(positionTicket, exitQueueIndex)
    await expect(tx).to.emit(poolEscrow, 'Withdrawn').withArgs(vault.address, vault.address, shares)
    await expect(tx)
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(other.address, positionTicket, 0, shares)
    expect(await waffle.provider.getBalance(poolEscrow.address)).to.eq(0)
    await snapshotGasCost(tx)
  })

  it('pulls assets on redeem', async () => {
    const shares = parseEther('10')
    await vault.connect(stakedEthToken).migrate(other.address, shares)

    await setBalance(vault.address, BigNumber.from(0))
    await setBalance(poolEscrow.address, shares)

    expect(await vault.withdrawableAssets()).to.eq(shares)

    const tx = await vault.connect(other).redeem(shares, other.address)
    await expect(tx)
      .to.emit(vault, 'Redeemed')
      .withArgs(other.address, other.address, shares, shares)
    await expect(tx).to.emit(poolEscrow, 'Withdrawn').withArgs(vault.address, vault.address, shares)
    expect(await waffle.provider.getBalance(poolEscrow.address)).to.eq(0)
  })

  it('pulls assets on single validator registration', async () => {
    const validatorDeposit = parseEther('32')
    await vault.connect(stakedEthToken).migrate(other.address, validatorDeposit)
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
    const validatorsData = await createEthValidatorsData(vault)
    const validatorsRegistryRoot = await validatorsRegistry.get_deposit_root()
    await vault.connect(admin).setValidatorsRoot(validatorsData.root)
    const proof = getValidatorsMultiProof(validatorsData.tree, validatorsData.validators, [
      ...Array(validatorsData.validators.length).keys(),
    ])
    const validators = validatorsData.validators
    const assets = parseEther('32').mul(validators.length)
    await vault.connect(stakedEthToken).migrate(other.address, assets)

    const sortedVals = proof.leaves.map((v) => v[0])
    const indexes = validators.map((v) => sortedVals.indexOf(v))
    await vault.connect(other).deposit(other.address, ZERO_ADDRESS, { value: assets })
    const exitSignaturesIpfsHash = exitSignatureIpfsHashes[0]
    const signingData = getEthValidatorsSigningData(
      Buffer.concat(validators),
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
    }

    await setBalance(vault.address, BigNumber.from(0))
    await setBalance(poolEscrow.address, assets)
    expect(await vault.withdrawableAssets()).to.eq(assets)

    const tx = await vault.registerValidators(approveParams, indexes, proof.proofFlags, proof.proof)
    await expect(tx).to.emit(poolEscrow, 'Withdrawn').withArgs(vault.address, vault.address, assets)
    await snapshotGasCost(tx)
  })
})
