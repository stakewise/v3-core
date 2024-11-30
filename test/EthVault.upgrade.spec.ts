import { ethers } from 'hardhat'
import { Contract, parseEther, Signer, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  DepositDataRegistry,
  EthVault,
  EthVault__factory,
  EthVaultFactory,
  EthVaultV4Mock,
  EthVaultV4Mock__factory,
  Keeper,
  OsTokenVaultController,
  SharedMevEscrow,
  VaultsRegistry,
  OsTokenConfig,
  IKeeperRewards,
} from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import {
  deployEthVaultImplementation,
  deployEthVaultV1,
  deployEthVaultV2,
  encodeEthErc20VaultInitParams,
  encodeEthVaultInitParams,
  ethVaultFixture,
} from './shared/fixtures'
import { expect } from './shared/expect'
import {
  EXITING_ASSETS_MIN_DELAY,
  MAX_UINT256,
  SECURITY_DEPOSIT,
  ZERO_ADDRESS,
} from './shared/constants'
import {
  collateralizeEthVault,
  getHarvestParams,
  getRewardsRootProof,
  updateRewards,
} from './shared/rewards'
import {
  getEthErc20VaultV2Factory,
  getEthGenesisVaultV2Factory,
  getEthPrivErc20VaultV2Factory,
  getEthPrivVaultV2Factory,
  getEthVaultV2Factory,
  getEthBlocklistVaultV2Factory,
  getEthBlocklistErc20VaultV2Factory,
  getEthVaultV1Factory,
} from './shared/contracts'
import { ThenArg } from '../helpers/types'
import { extractExitPositionTicket, getBlockTimestamp, setBalance } from './shared/utils'

describe('EthVault - upgrade', () => {
  const capacity = ethers.parseEther('1000')
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7r'
  let admin: Signer, dao: Wallet, other: Wallet
  let vault: EthVault,
    vaultsRegistry: VaultsRegistry,
    keeper: Keeper,
    validatorsRegistry: Contract,
    updatedVault: EthVaultV4Mock,
    sharedMevEscrow: SharedMevEscrow,
    osTokenConfig: OsTokenConfig,
    osTokenVaultController: OsTokenVaultController,
    depositDataRegistry: DepositDataRegistry,
    ethVaultFactory: EthVaultFactory,
    ethPrivVaultFactory: EthVaultFactory,
    ethBlocklistVaultFactory: EthVaultFactory,
    ethErc20VaultFactory: EthVaultFactory,
    ethPrivErc20VaultFactory: EthVaultFactory,
    ethBlocklistErc20VaultFactory: EthVaultFactory
  let currImpl: string
  let mockImpl: string
  let callData: string
  let fixture: any

  let createGenesisVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthGenesisVault']

  beforeEach('deploy fixture', async () => {
    ;[dao, admin, other] = await (ethers as any).getSigners()
    fixture = await loadFixture(ethVaultFixture)
    vaultsRegistry = fixture.vaultsRegistry
    validatorsRegistry = fixture.validatorsRegistry
    keeper = fixture.keeper
    sharedMevEscrow = fixture.sharedMevEscrow
    osTokenVaultController = fixture.osTokenVaultController
    depositDataRegistry = fixture.depositDataRegistry
    ethVaultFactory = fixture.ethVaultFactory
    ethPrivVaultFactory = fixture.ethPrivVaultFactory
    ethBlocklistVaultFactory = fixture.ethBlocklistVaultFactory
    ethErc20VaultFactory = fixture.ethErc20VaultFactory
    ethPrivErc20VaultFactory = fixture.ethPrivErc20VaultFactory
    ethBlocklistErc20VaultFactory = fixture.ethBlocklistErc20VaultFactory
    createGenesisVault = fixture.createEthGenesisVault
    osTokenConfig = fixture.osTokenConfig
    vault = await fixture.createEthVault(admin, {
      capacity,
      feePercent,
      metadataIpfsHash,
    })
    admin = await ethers.getImpersonatedSigner(await vault.admin())

    mockImpl = await deployEthVaultImplementation(
      'EthVaultV4Mock',
      fixture.keeper,
      fixture.vaultsRegistry,
      await fixture.validatorsRegistry.getAddress(),
      fixture.osTokenVaultController,
      fixture.osTokenConfig,
      fixture.osTokenVaultEscrow,
      fixture.sharedMevEscrow,
      fixture.depositDataRegistry,
      EXITING_ASSETS_MIN_DELAY
    )
    currImpl = await vault.implementation()
    callData = ethers.AbiCoder.defaultAbiCoder().encode(['uint128'], [100])
    await vaultsRegistry.connect(dao).addVaultImpl(mockImpl)
    updatedVault = EthVaultV4Mock__factory.connect(
      await vault.getAddress(),
      await ethers.provider.getSigner()
    )
  })

  it('fails from not admin', async () => {
    await expect(
      vault.connect(other).upgradeToAndCall(mockImpl, callData)
    ).to.revertedWithCustomError(vault, 'AccessDenied')
    expect(await vault.version()).to.be.eq(3)
  })

  it('fails with zero new implementation address', async () => {
    await expect(
      vault.connect(admin).upgradeToAndCall(ZERO_ADDRESS, callData)
    ).to.revertedWithCustomError(vault, 'UpgradeFailed')
    expect(await vault.version()).to.be.eq(3)
  })

  it('fails for the same implementation', async () => {
    await expect(
      vault.connect(admin).upgradeToAndCall(currImpl, callData)
    ).to.revertedWithCustomError(vault, 'UpgradeFailed')
    expect(await vault.version()).to.be.eq(3)
  })

  it('fails for not approved implementation', async () => {
    await vaultsRegistry.connect(dao).removeVaultImpl(mockImpl)
    await expect(
      vault.connect(admin).upgradeToAndCall(mockImpl, callData)
    ).to.revertedWithCustomError(vault, 'UpgradeFailed')
    expect(await vault.version()).to.be.eq(3)
  })

  it('fails for implementation with different vault id', async () => {
    const newImpl = await deployEthVaultImplementation(
      'EthPrivVaultV4Mock',
      fixture.keeper,
      fixture.vaultsRegistry,
      await fixture.validatorsRegistry.getAddress(),
      fixture.osTokenVaultController,
      fixture.osTokenConfig,
      fixture.osTokenVaultEscrow,
      fixture.sharedMevEscrow,
      fixture.depositDataRegistry,
      EXITING_ASSETS_MIN_DELAY
    )
    callData = ethers.AbiCoder.defaultAbiCoder().encode(['uint128'], [100])
    await vaultsRegistry.connect(dao).addVaultImpl(newImpl)
    await expect(
      vault.connect(admin).upgradeToAndCall(newImpl, callData)
    ).to.revertedWithCustomError(vault, 'UpgradeFailed')
    expect(await vault.version()).to.be.eq(3)
  })

  it('fails for implementation with too high version', async () => {
    const newImpl = await deployEthVaultImplementation(
      'EthVaultV5Mock',
      fixture.keeper,
      fixture.vaultsRegistry,
      await fixture.validatorsRegistry.getAddress(),
      fixture.osTokenVaultController,
      fixture.osTokenConfig,
      fixture.osTokenVaultEscrow,
      fixture.sharedMevEscrow,
      fixture.depositDataRegistry,
      EXITING_ASSETS_MIN_DELAY
    )
    callData = ethers.AbiCoder.defaultAbiCoder().encode(['uint128'], [100])
    await vaultsRegistry.connect(dao).addVaultImpl(newImpl)
    await expect(
      vault.connect(admin).upgradeToAndCall(newImpl, callData)
    ).to.revertedWithCustomError(vault, 'UpgradeFailed')
    expect(await vault.version()).to.be.eq(3)
  })

  it('fails with invalid call data', async () => {
    await expect(
      vault
        .connect(admin)
        .upgradeToAndCall(
          mockImpl,
          ethers.AbiCoder.defaultAbiCoder().encode(['uint256'], [MAX_UINT256])
        )
    ).to.revertedWithCustomError(vault, 'FailedInnerCall')
    expect(await vault.version()).to.be.eq(3)
  })

  it('works with valid call data', async () => {
    const receipt = await vault.connect(admin).upgradeToAndCall(mockImpl, callData)
    expect(await vault.version()).to.be.eq(4)
    expect(await vault.implementation()).to.be.eq(mockImpl)
    expect(await updatedVault.newVar()).to.be.eq(100)
    expect(await updatedVault.somethingNew()).to.be.eq(true)
    await expect(
      vault.connect(admin).upgradeToAndCall(mockImpl, callData)
    ).to.revertedWithCustomError(vault, 'UpgradeFailed')
    await expect(updatedVault.connect(admin).initialize(callData)).to.revertedWithCustomError(
      updatedVault,
      'InvalidInitialization'
    )
    await snapshotGasCost(receipt)
  })

  it('fails with pending queued shares', async () => {
    // deploy v1 vault and create exit position
    const vaultV1Factory = await getEthVaultV1Factory()
    const vaultV1 = await deployEthVaultV1(
      vaultV1Factory,
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
    await collateralizeEthVault(vaultV1, keeper, depositDataRegistry, admin, validatorsRegistry)
    const assets = parseEther('3')
    await vaultV1.connect(other).deposit(other.address, ZERO_ADDRESS, { value: assets })
    const vaultV1ExitingShares = await vaultV1.convertToShares(assets / 3n)
    let tx = await vaultV1.connect(other).enterExitQueue(vaultV1ExitingShares, other.address)
    expect(await vaultV1.version()).to.be.eq(1)
    expect(await vaultV1.queuedShares()).to.be.eq(vaultV1ExitingShares)
    const positionTicket1 = await extractExitPositionTicket(tx)
    const timestamp1 = await getBlockTimestamp(tx)

    // create v2 vault impl and upgrade
    const vaultV2Factory = await getEthVaultV2Factory()
    const constructorArgs = [
      await keeper.getAddress(),
      await vaultsRegistry.getAddress(),
      await validatorsRegistry.getAddress(),
      await osTokenVaultController.getAddress(),
      await osTokenConfig.getAddress(),
      await sharedMevEscrow.getAddress(),
      await depositDataRegistry.getAddress(),
      EXITING_ASSETS_MIN_DELAY,
    ]
    const vaultImplV2 = await vaultV2Factory.deploy(...constructorArgs)
    const vaultImplV2Addr = await vaultImplV2.getAddress()
    await vaultsRegistry.addVaultImpl(vaultImplV2Addr)

    // upgrade vault to v2
    const vaultV2 = new Contract(await vaultV1.getAddress(), vaultImplV2.interface, admin)
    await vaultV2.connect(admin).upgradeToAndCall(vaultImplV2Addr, '0x')
    expect(await vaultV2.version()).to.be.eq(2)

    // enter the exit queue
    const vaultV2ExitingShares = await vaultV2.convertToShares(assets / 3n)
    tx = await vaultV2.connect(other).enterExitQueue(vaultV2ExitingShares, other.address)
    const positionTicket2 = await extractExitPositionTicket(tx)
    const timestamp2 = await getBlockTimestamp(tx)
    expect(await vaultV2.totalExitingAssets()).to.be.eq(vaultV2ExitingShares)
    expect(await vaultV2.queuedShares()).to.be.eq(vaultV1ExitingShares)

    // try to upgrade with pending shares
    const vaultImplV3Addr = await ethVaultFactory.implementation()
    const vaultV3 = EthVault__factory.connect(await vaultV2.getAddress(), admin)
    await expect(
      vaultV3.connect(admin).upgradeToAndCall(vaultImplV3Addr, '0x')
    ).to.revertedWithCustomError(vaultV3, 'InvalidQueuedShares')

    // leave one asset in the queue shares
    let vaultBalance = assets / 3n - 1n
    await setBalance(await vaultV2.getAddress(), vaultBalance)
    let vaultReward = getHarvestParams(await vaultV2.getAddress(), 0n, 0n)
    let tree = await updateRewards(keeper, [vaultReward], 0)
    let harvestParams: IKeeperRewards.HarvestParamsStruct = {
      rewardsRoot: tree.root,
      reward: vaultReward.reward,
      unlockedMevReward: vaultReward.unlockedMevReward,
      proof: getRewardsRootProof(tree, vaultReward),
    }
    await expect(vaultV2.connect(dao).updateState(harvestParams))
      .to.emit(vaultV2, 'CheckpointCreated')
      .withArgs(await vaultV2.convertToShares(vaultBalance), vaultBalance)
    expect(await vaultV2.queuedShares()).to.be.eq(1n)
    expect(await vaultV2.totalExitingAssets()).to.be.eq(vaultV2ExitingShares)

    // upgrade to v3
    expect(await vaultV3.queuedShares()).to.be.eq(1n)
    tx = await vaultV3.connect(admin).upgradeToAndCall(vaultImplV3Addr, '0x')
    expect(await vaultV3.version()).to.be.eq(3)
    await expect(tx).to.emit(vaultV3, 'CheckpointCreated').withArgs(1n, 0)
    expect(await vaultV3.queuedShares()).to.be.eq(0n)

    // enter exit queue for the rest of the assets
    const vaultV3ExitingShares = await vaultV3.getShares(other.address)
    tx = await vaultV3.connect(other).enterExitQueue(vaultV3ExitingShares, other.address)
    const positionTicket3 = await extractExitPositionTicket(tx)
    const timestamp3 = await getBlockTimestamp(tx)
    expect(await vaultV3.queuedShares()).to.be.eq(vaultV3ExitingShares)

    // penalty received for the vault
    const halfTotalAssets = (await vaultV3.totalAssets()) / 2n
    vaultReward = getHarvestParams(await vaultV3.getAddress(), -halfTotalAssets, 0n)
    tree = await updateRewards(keeper, [vaultReward], 0)
    harvestParams = {
      rewardsRoot: tree.root,
      reward: vaultReward.reward,
      unlockedMevReward: vaultReward.unlockedMevReward,
      proof: getRewardsRootProof(tree, vaultReward),
    }
    tx = await vaultV3.connect(dao).updateState(harvestParams)
    await expect(tx)
      .to.emit(vaultV3, 'ExitingAssetsPenalized')
      .withArgs(
        (halfTotalAssets * vaultV2ExitingShares) /
          (vaultV2ExitingShares + vaultV3ExitingShares + SECURITY_DEPOSIT)
      )
    await expect(tx).to.not.emit(vaultV3, 'CheckpointCreated')

    // does not emit checkpoint when there is not enough assets to finish v2 exit queue
    vaultBalance += 1n
    await setBalance(await vaultV3.getAddress(), vaultBalance)
    tree = await updateRewards(keeper, [vaultReward], 0)
    harvestParams = {
      rewardsRoot: tree.root,
      reward: vaultReward.reward,
      unlockedMevReward: vaultReward.unlockedMevReward,
      proof: getRewardsRootProof(tree, vaultReward),
    }
    tx = await vaultV3.connect(dao).updateState(harvestParams)
    await expect(tx).to.not.emit(vaultV3, 'CheckpointCreated')

    // emits checkpoints when there is enough assets to finish v2 exit queue
    await setBalance(await vaultV3.getAddress(), assets + SECURITY_DEPOSIT - halfTotalAssets)
    tree = await updateRewards(keeper, [vaultReward], 0)
    harvestParams = {
      rewardsRoot: tree.root,
      reward: vaultReward.reward,
      unlockedMevReward: vaultReward.unlockedMevReward,
      proof: getRewardsRootProof(tree, vaultReward),
    }
    tx = await vaultV3.connect(dao).updateState(harvestParams)
    await expect(tx).to.emit(vaultV3, 'CheckpointCreated')
    expect(await vaultV3.queuedShares()).to.be.eq(1n)

    await vaultV3
      .connect(other)
      .claimExitedAssets(
        positionTicket1,
        timestamp1,
        await vaultV3.getExitQueueIndex(positionTicket1)
      )
    await vaultV3
      .connect(other)
      .claimExitedAssets(
        positionTicket2,
        timestamp2,
        await vaultV3.getExitQueueIndex(positionTicket2)
      )
    await vaultV3
      .connect(other)
      .claimExitedAssets(
        positionTicket3,
        timestamp3,
        await vaultV3.getExitQueueIndex(positionTicket3)
      )

    const queuedShares = 1n
    const totalShares = (await vaultV3.getShares(await vaultV3.getAddress())) + queuedShares
    const totalAssets = await vaultV3.convertToAssets(totalShares)
    expect(await vaultV3.totalShares()).to.be.eq(totalShares)
    expect(await vaultV3.totalAssets()).to.be.eq(totalAssets)
    expect(await vaultV3.queuedShares()).to.be.eq(queuedShares)
  })

  it('does not modify the state variables', async () => {
    const vaults: Contract[] = []
    for (const factory of [
      await getEthVaultV2Factory(),
      await getEthPrivVaultV2Factory(),
      await getEthBlocklistVaultV2Factory(),
    ]) {
      const vault = await deployEthVaultV2(
        factory,
        admin,
        keeper,
        vaultsRegistry,
        validatorsRegistry,
        osTokenVaultController,
        osTokenConfig,
        sharedMevEscrow,
        depositDataRegistry,
        encodeEthVaultInitParams({
          capacity,
          feePercent,
          metadataIpfsHash,
        })
      )
      vaults.push(vault)
    }
    for (const factory of [
      await getEthErc20VaultV2Factory(),
      await getEthPrivErc20VaultV2Factory(),
      await getEthBlocklistErc20VaultV2Factory(),
    ]) {
      const vault = await deployEthVaultV2(
        factory,
        admin,
        keeper,
        vaultsRegistry,
        validatorsRegistry,
        osTokenVaultController,
        osTokenConfig,
        sharedMevEscrow,
        depositDataRegistry,
        encodeEthErc20VaultInitParams({
          capacity,
          feePercent,
          metadataIpfsHash,
          name: 'Vault',
          symbol: 'VLT',
        })
      )
      vaults.push(vault)
    }

    const checkVault = async (vault: Contract, newImpl: string) => {
      await collateralizeEthVault(vault, keeper, depositDataRegistry, admin, validatorsRegistry)
      await vault.connect(other).deposit(other.address, ZERO_ADDRESS, { value: parseEther('3') })
      await vault.connect(other).enterExitQueue(parseEther('1'), other.address)
      await vault.connect(other).mintOsToken(other.address, parseEther('1'), ZERO_ADDRESS)

      const userShares = await vault.getShares(other.address)
      const userAssets = await vault.convertToAssets(userShares)
      const osTokenPosition = await vault.osTokenPositions(other.address)
      const mevEscrow = await vault.mevEscrow()
      const totalAssets = await vault.totalAssets()
      const totalShares = await vault.totalShares()
      const vaultAddress = await vault.getAddress()
      expect(await vault.version()).to.be.eq(2)

      const receipt = await vault.connect(admin).upgradeToAndCall(newImpl, '0x')
      const vaultV3 = EthVault__factory.connect(vaultAddress, admin)
      expect(await vaultV3.version()).to.be.eq(3)
      expect(await vaultV3.implementation()).to.be.eq(newImpl)
      expect(await vaultV3.getShares(other.address)).to.be.eq(userShares)
      expect(await vaultV3.convertToAssets(userShares)).to.be.deep.eq(userAssets)
      expect(await vaultV3.osTokenPositions(other.address)).to.be.above(osTokenPosition)
      expect(await vaultV3.validatorsManager()).to.be.eq(await depositDataRegistry.getAddress())
      expect(await vaultV3.mevEscrow()).to.be.eq(mevEscrow)
      expect(await vaultV3.totalAssets()).to.be.eq(totalAssets)
      expect(await vaultV3.totalShares()).to.be.eq(totalShares)
      await snapshotGasCost(receipt)
    }
    await checkVault(vaults[0], await ethVaultFactory.implementation())
    await vaults[1].connect(admin).updateWhitelist(other.address, true)
    await checkVault(vaults[1], await ethPrivVaultFactory.implementation())
    await checkVault(vaults[2], await ethBlocklistVaultFactory.implementation())

    await checkVault(vaults[3], await ethErc20VaultFactory.implementation())
    await vaults[4].connect(admin).updateWhitelist(other.address, true)
    await checkVault(vaults[4], await ethPrivErc20VaultFactory.implementation())
    await checkVault(vaults[5], await ethBlocklistErc20VaultFactory.implementation())

    const [v3GenesisVault, rewardEthToken, poolEscrow] = await createGenesisVault(
      admin,
      {
        capacity,
        feePercent,
        metadataIpfsHash,
      },
      true
    )
    const factory = await getEthGenesisVaultV2Factory()
    const constructorArgs = [
      await keeper.getAddress(),
      await vaultsRegistry.getAddress(),
      await validatorsRegistry.getAddress(),
      await osTokenVaultController.getAddress(),
      await osTokenConfig.getAddress(),
      await sharedMevEscrow.getAddress(),
      await depositDataRegistry.getAddress(),
      await poolEscrow.getAddress(),
      await rewardEthToken.getAddress(),
      EXITING_ASSETS_MIN_DELAY,
    ]
    const contract = await factory.deploy(...constructorArgs)
    const genesisImpl = await contract.getAddress()
    const genesisImplV3 = await v3GenesisVault.implementation()
    await vaultsRegistry.addVaultImpl(genesisImpl)

    const proxyFactory = await ethers.getContractFactory('ERC1967Proxy')
    const proxy = await proxyFactory.deploy(genesisImpl, '0x')
    const proxyAddress = await proxy.getAddress()
    const genesisVault = new Contract(proxyAddress, contract.interface, admin)
    await rewardEthToken.connect(dao).setVault(proxyAddress)
    await poolEscrow.connect(dao).commitOwnershipTransfer(proxyAddress)
    await genesisVault.initialize(
      ethers.AbiCoder.defaultAbiCoder().encode(
        ['address', 'tuple(uint256 capacity, uint16 feePercent, string metadataIpfsHash)'],
        [await admin.getAddress(), [capacity, feePercent, metadataIpfsHash]]
      ),
      { value: SECURITY_DEPOSIT }
    )
    await genesisVault.acceptPoolEscrowOwnership()
    await vaultsRegistry.addVault(proxyAddress)
    await checkVault(genesisVault, genesisImplV3)
  })
})
