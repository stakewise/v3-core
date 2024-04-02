import { ethers } from 'hardhat'
import { Contract, parseEther, Signer, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  DepositDataRegistry,
  EthVault,
  EthVault__factory,
  EthVaultFactory,
  EthVaultV3Mock,
  EthVaultV3Mock__factory,
  Keeper,
  OsTokenConfig,
  OsTokenVaultController,
  SharedMevEscrow,
  VaultsRegistry,
} from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import {
  deployEthVaultImplementation,
  deployEthVaultV1,
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
import { collateralizeEthV1Vault } from './shared/rewards'
import {
  getEthErc20VaultV1Factory,
  getEthGenesisVaultV1Factory,
  getEthPrivErc20VaultV1Factory,
  getEthPrivVaultV1Factory,
  getEthVaultV1Factory,
} from './shared/contracts'
import { ThenArg } from '../helpers/types'

describe('EthVault - upgrade', () => {
  const capacity = ethers.parseEther('1000')
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7r'
  let admin: Signer, dao: Wallet, other: Wallet
  let vault: EthVault,
    vaultsRegistry: VaultsRegistry,
    keeper: Keeper,
    validatorsRegistry: Contract,
    updatedVault: EthVaultV3Mock,
    sharedMevEscrow: SharedMevEscrow,
    osTokenConfig: OsTokenConfig,
    osTokenVaultController: OsTokenVaultController,
    depositDataRegistry: DepositDataRegistry,
    ethVaultFactory: EthVaultFactory,
    ethPrivVaultFactory: EthVaultFactory,
    ethErc20VaultFactory: EthVaultFactory,
    ethPrivErc20VaultFactory: EthVaultFactory
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
    osTokenConfig = fixture.osTokenConfig
    osTokenVaultController = fixture.osTokenVaultController
    depositDataRegistry = fixture.depositDataRegistry
    ethVaultFactory = fixture.ethVaultFactory
    ethPrivVaultFactory = fixture.ethPrivVaultFactory
    ethErc20VaultFactory = fixture.ethErc20VaultFactory
    ethPrivErc20VaultFactory = fixture.ethPrivErc20VaultFactory
    createGenesisVault = fixture.createEthGenesisVault
    vault = await fixture.createEthVault(admin, {
      capacity,
      feePercent,
      metadataIpfsHash,
    })
    admin = await ethers.getImpersonatedSigner(await vault.admin())

    mockImpl = await deployEthVaultImplementation(
      'EthVaultV3Mock',
      fixture.keeper,
      fixture.vaultsRegistry,
      await fixture.validatorsRegistry.getAddress(),
      fixture.osTokenVaultController,
      fixture.osTokenConfig,
      fixture.sharedMevEscrow,
      fixture.depositDataRegistry,
      EXITING_ASSETS_MIN_DELAY
    )
    currImpl = await vault.implementation()
    callData = ethers.AbiCoder.defaultAbiCoder().encode(['uint128'], [100])
    await vaultsRegistry.connect(dao).addVaultImpl(mockImpl)
    updatedVault = EthVaultV3Mock__factory.connect(
      await vault.getAddress(),
      await ethers.provider.getSigner()
    )
  })

  it('fails from not admin', async () => {
    await expect(
      vault.connect(other).upgradeToAndCall(mockImpl, callData)
    ).to.revertedWithCustomError(vault, 'AccessDenied')
    expect(await vault.version()).to.be.eq(2)
  })

  it('fails with zero new implementation address', async () => {
    await expect(
      vault.connect(admin).upgradeToAndCall(ZERO_ADDRESS, callData)
    ).to.revertedWithCustomError(vault, 'UpgradeFailed')
    expect(await vault.version()).to.be.eq(2)
  })

  it('fails for the same implementation', async () => {
    await expect(
      vault.connect(admin).upgradeToAndCall(currImpl, callData)
    ).to.revertedWithCustomError(vault, 'UpgradeFailed')
    expect(await vault.version()).to.be.eq(2)
  })

  it('fails for not approved implementation', async () => {
    await vaultsRegistry.connect(dao).removeVaultImpl(mockImpl)
    await expect(
      vault.connect(admin).upgradeToAndCall(mockImpl, callData)
    ).to.revertedWithCustomError(vault, 'UpgradeFailed')
    expect(await vault.version()).to.be.eq(2)
  })

  it('fails for implementation with different vault id', async () => {
    const newImpl = await deployEthVaultImplementation(
      'EthPrivVaultV3Mock',
      fixture.keeper,
      fixture.vaultsRegistry,
      await fixture.validatorsRegistry.getAddress(),
      fixture.osTokenVaultController,
      fixture.osTokenConfig,
      fixture.sharedMevEscrow,
      fixture.depositDataRegistry,
      EXITING_ASSETS_MIN_DELAY
    )
    callData = ethers.AbiCoder.defaultAbiCoder().encode(['uint128'], [100])
    await vaultsRegistry.connect(dao).addVaultImpl(newImpl)
    await expect(
      vault.connect(admin).upgradeToAndCall(newImpl, callData)
    ).to.revertedWithCustomError(vault, 'UpgradeFailed')
    expect(await vault.version()).to.be.eq(2)
  })

  it('fails for implementation with too high version', async () => {
    const newImpl = await deployEthVaultImplementation(
      'EthVaultV4Mock',
      fixture.keeper,
      fixture.vaultsRegistry,
      await fixture.validatorsRegistry.getAddress(),
      fixture.osTokenVaultController,
      fixture.osTokenConfig,
      fixture.sharedMevEscrow,
      fixture.depositDataRegistry,
      EXITING_ASSETS_MIN_DELAY
    )
    callData = ethers.AbiCoder.defaultAbiCoder().encode(['uint128'], [100])
    await vaultsRegistry.connect(dao).addVaultImpl(newImpl)
    await expect(
      vault.connect(admin).upgradeToAndCall(newImpl, callData)
    ).to.revertedWithCustomError(vault, 'UpgradeFailed')
    expect(await vault.version()).to.be.eq(2)
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
    expect(await vault.version()).to.be.eq(2)
  })

  it('works with valid call data', async () => {
    const receipt = await vault.connect(admin).upgradeToAndCall(mockImpl, callData)
    expect(await vault.version()).to.be.eq(3)
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

  it('works with valid call data', async () => {
    const receipt = await vault.connect(admin).upgradeToAndCall(mockImpl, callData)
    expect(await vault.version()).to.be.eq(3)
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

  it('does not modify the state variables', async () => {
    const vaults: Contract[] = []
    for (const factory of [await getEthVaultV1Factory(), await getEthPrivVaultV1Factory()]) {
      const vault = await deployEthVaultV1(
        factory,
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
      vaults.push(vault)
    }
    for (const factory of [
      await getEthErc20VaultV1Factory(),
      await getEthPrivErc20VaultV1Factory(),
    ]) {
      const vault = await deployEthVaultV1(
        factory,
        admin,
        keeper,
        vaultsRegistry,
        validatorsRegistry,
        osTokenVaultController,
        osTokenConfig,
        sharedMevEscrow,
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
      await collateralizeEthV1Vault(vault, keeper, validatorsRegistry, admin)
      await vault.connect(other).deposit(other.address, ZERO_ADDRESS, { value: parseEther('3') })
      await vault.connect(other).enterExitQueue(parseEther('1'), other.address)
      await vault.connect(other).mintOsToken(other.address, parseEther('1'), ZERO_ADDRESS)

      const userShares = await vault.getShares(other.address)
      const userAssets = await vault.convertToAssets(userShares)
      const osTokenPosition = await vault.osTokenPositions(other.address)
      const mevEscrow = await vault.mevEscrow()
      const totalAssets = await vault.totalAssets()
      const totalShares = await vault.totalShares()
      const validatorIndex = await vault.validatorIndex()
      const validatorsRoot = await vault.validatorsRoot()
      const vaultAddress = await vault.getAddress()
      expect(await vault.version()).to.be.eq(1)

      const receipt = await vault.connect(admin).upgradeToAndCall(newImpl, '0x')
      const vaultV2 = EthVault__factory.connect(vaultAddress, admin)
      expect(await vaultV2.version()).to.be.eq(2)
      expect(await vaultV2.implementation()).to.be.eq(newImpl)
      expect(await vaultV2.getShares(other.address)).to.be.eq(userShares)
      expect(await vaultV2.convertToAssets(userShares)).to.be.deep.eq(userAssets)
      expect(await vaultV2.osTokenPositions(other.address)).to.be.above(osTokenPosition)
      expect(await vaultV2.validatorsManager()).to.be.eq(await depositDataRegistry.getAddress())
      expect(await vaultV2.mevEscrow()).to.be.eq(mevEscrow)
      expect(await vaultV2.totalAssets()).to.be.eq(totalAssets)
      expect(await vaultV2.totalShares()).to.be.eq(totalShares)
      expect(await depositDataRegistry.depositDataIndexes(vaultAddress)).to.be.eq(validatorIndex)
      expect(await depositDataRegistry.depositDataRoots(vaultAddress)).to.be.eq(validatorsRoot)
      await snapshotGasCost(receipt)
    }
    await checkVault(vaults[0], await ethVaultFactory.implementation())
    await checkVault(vaults[2], await ethErc20VaultFactory.implementation())

    await vaults[1].connect(admin).updateWhitelist(other.address, true)
    await checkVault(vaults[1], await ethPrivVaultFactory.implementation())

    await vaults[3].connect(admin).updateWhitelist(other.address, true)
    await checkVault(vaults[3], await ethPrivErc20VaultFactory.implementation())

    const [v2GenesisVault, rewardEthToken, poolEscrow] = await createGenesisVault(
      admin,
      {
        capacity,
        feePercent,
        metadataIpfsHash,
      },
      true
    )
    const factory = await getEthGenesisVaultV1Factory()
    const constructorArgs = [
      await keeper.getAddress(),
      await vaultsRegistry.getAddress(),
      await validatorsRegistry.getAddress(),
      await osTokenVaultController.getAddress(),
      await osTokenConfig.getAddress(),
      await sharedMevEscrow.getAddress(),
      await poolEscrow.getAddress(),
      await rewardEthToken.getAddress(),
      EXITING_ASSETS_MIN_DELAY,
    ]
    const contract = await factory.deploy(...constructorArgs)
    const genesisImpl = await contract.getAddress()
    const genesisImplV2 = await v2GenesisVault.implementation()
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
    await checkVault(genesisVault, genesisImplV2)
  })
})
