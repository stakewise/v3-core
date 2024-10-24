import { ethers } from 'hardhat'
import { Contract, parseEther, Signer, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  DepositDataRegistry,
  GnoVault__factory,
  GnoVaultFactory,
  Keeper,
  OsTokenConfig,
  OsTokenVaultController,
  SharedMevEscrow,
  VaultsRegistry,
  XdaiExchange,
  ERC20Mock,
} from '../../typechain-types'
import snapshotGasCost from '../shared/snapshotGasCost'
import {
  approveSecurityDeposit,
  deployGnoVaultV2,
  depositGno,
  encodeGnoErc20VaultInitParams,
  encodeGnoVaultInitParams,
  gnoVaultFixture,
} from '../shared/gnoFixtures'
import { expect } from '../shared/expect'
import { EXITING_ASSETS_MIN_DELAY, ZERO_ADDRESS } from '../shared/constants'
import { collateralizeGnoVault } from '../shared/gnoFixtures'
import {
  getGnoBlocklistErc20VaultV2Factory,
  getGnoBlocklistVaultV2Factory,
  getGnoErc20VaultV2Factory,
  getGnoGenesisVaultV2Factory,
  getGnoPrivErc20VaultV2Factory,
  getGnoPrivVaultV2Factory,
  getGnoVaultV2Factory,
} from '../shared/contracts'
import { ThenArg } from '../../helpers/types'

describe('GnoVault - upgrade', () => {
  const capacity = ethers.parseEther('1000')
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7r'
  let admin: Signer, dao: Wallet, other: Wallet
  let vaultsRegistry: VaultsRegistry,
    keeper: Keeper,
    validatorsRegistry: Contract,
    sharedMevEscrow: SharedMevEscrow,
    osTokenConfig: OsTokenConfig,
    osTokenVaultController: OsTokenVaultController,
    depositDataRegistry: DepositDataRegistry,
    xdaiExchange: XdaiExchange,
    gnoToken: ERC20Mock,
    gnoVaultFactory: GnoVaultFactory,
    gnoPrivVaultFactory: GnoVaultFactory,
    gnoBlocklistVaultFactory: GnoVaultFactory,
    gnoErc20VaultFactory: GnoVaultFactory,
    gnoPrivErc20VaultFactory: GnoVaultFactory,
    gnoBlocklistErc20VaultFactory: GnoVaultFactory
  let fixture: any

  let createGenesisVault: ThenArg<ReturnType<typeof gnoVaultFixture>>['createGnoGenesisVault']

  beforeEach('deploy fixture', async () => {
    ;[dao, admin, other] = await (ethers as any).getSigners()
    fixture = await loadFixture(gnoVaultFixture)
    vaultsRegistry = fixture.vaultsRegistry
    validatorsRegistry = fixture.validatorsRegistry
    keeper = fixture.keeper
    sharedMevEscrow = fixture.sharedMevEscrow
    osTokenVaultController = fixture.osTokenVaultController
    depositDataRegistry = fixture.depositDataRegistry
    gnoVaultFactory = fixture.gnoVaultFactory
    gnoPrivVaultFactory = fixture.gnoPrivVaultFactory
    gnoBlocklistVaultFactory = fixture.gnoBlocklistVaultFactory
    gnoErc20VaultFactory = fixture.gnoErc20VaultFactory
    gnoPrivErc20VaultFactory = fixture.gnoPrivErc20VaultFactory
    gnoBlocklistErc20VaultFactory = fixture.gnoBlocklistErc20VaultFactory
    createGenesisVault = fixture.createGnoGenesisVault
    osTokenConfig = fixture.osTokenConfig
    xdaiExchange = fixture.xdaiExchange
    gnoToken = fixture.gnoToken
  })

  it('does not modify the state variables', async () => {
    const vaults: Contract[] = []
    for (const factory of [
      await getGnoVaultV2Factory(),
      await getGnoPrivVaultV2Factory(),
      await getGnoBlocklistVaultV2Factory(),
    ]) {
      const vault = await deployGnoVaultV2(
        factory,
        admin,
        keeper,
        vaultsRegistry,
        validatorsRegistry,
        osTokenVaultController,
        osTokenConfig,
        sharedMevEscrow,
        depositDataRegistry,
        gnoToken,
        xdaiExchange,
        encodeGnoVaultInitParams({
          capacity,
          feePercent,
          metadataIpfsHash,
        })
      )
      vaults.push(vault)
    }
    for (const factory of [
      await getGnoErc20VaultV2Factory(),
      await getGnoPrivErc20VaultV2Factory(),
      await getGnoBlocklistErc20VaultV2Factory(),
    ]) {
      const vault = await deployGnoVaultV2(
        factory,
        admin,
        keeper,
        vaultsRegistry,
        validatorsRegistry,
        osTokenVaultController,
        osTokenConfig,
        sharedMevEscrow,
        depositDataRegistry,
        gnoToken,
        xdaiExchange,
        encodeGnoErc20VaultInitParams({
          capacity,
          feePercent,
          metadataIpfsHash,
          name: 'Vault',
          symbol: 'VLT',
        })
      )
      vaults.push(vault)
    }

    const checkVault = async (vault: Contract, newImpl: string, isGenesis: boolean = false) => {
      await collateralizeGnoVault(
        vault,
        gnoToken,
        keeper,
        depositDataRegistry,
        admin,
        validatorsRegistry
      )
      await depositGno(vault, gnoToken, parseEther('3'), other, other, ZERO_ADDRESS)
      await vault.connect(other).enterExitQueue(parseEther('1'), other.address)
      await vault.connect(other).mintOsToken(other.address, parseEther('1'), ZERO_ADDRESS)

      const userShares = await vault.getShares(other.address)
      const userAssets = await vault.convertToAssets(userShares)
      const osTokenPosition = await vault.osTokenPositions(other.address)
      const mevEscrow = await vault.mevEscrow()
      const totalAssets = await vault.totalAssets()
      const totalShares = await vault.totalShares()
      const vaultAddress = await vault.getAddress()
      expect(await vault.version()).to.be.eq(isGenesis ? 3 : 2)

      const receipt = await vault.connect(admin).upgradeToAndCall(newImpl, '0x')
      const vaultV3 = GnoVault__factory.connect(vaultAddress, admin)
      expect(await vaultV3.version()).to.be.eq(isGenesis ? 4 : 3)
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
    await checkVault(vaults[0], await gnoVaultFactory.implementation())
    await vaults[1].connect(admin).updateWhitelist(other.address, true)
    await checkVault(vaults[1], await gnoPrivVaultFactory.implementation())
    await checkVault(vaults[2], await gnoBlocklistVaultFactory.implementation())

    await checkVault(vaults[3], await gnoErc20VaultFactory.implementation())
    await vaults[4].connect(admin).updateWhitelist(other.address, true)
    await checkVault(vaults[4], await gnoPrivErc20VaultFactory.implementation())
    await checkVault(vaults[5], await gnoBlocklistErc20VaultFactory.implementation())

    const [v3GenesisVault, rewardGnoToken, poolEscrow] = await createGenesisVault(
      admin,
      {
        capacity,
        feePercent,
        metadataIpfsHash,
      },
      true
    )
    const factory = await getGnoGenesisVaultV2Factory()
    const constructorArgs = [
      await keeper.getAddress(),
      await vaultsRegistry.getAddress(),
      await validatorsRegistry.getAddress(),
      await osTokenVaultController.getAddress(),
      await osTokenConfig.getAddress(),
      await sharedMevEscrow.getAddress(),
      await depositDataRegistry.getAddress(),
      await gnoToken.getAddress(),
      await xdaiExchange.getAddress(),
      await poolEscrow.getAddress(),
      await rewardGnoToken.getAddress(),
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
    await rewardGnoToken.connect(dao).setVault(proxyAddress)
    await poolEscrow.connect(dao).commitOwnershipTransfer(proxyAddress)
    await approveSecurityDeposit(await genesisVault.getAddress(), gnoToken, admin)
    await genesisVault.initialize(
      ethers.AbiCoder.defaultAbiCoder().encode(
        ['address', 'tuple(uint256 capacity, uint16 feePercent, string metadataIpfsHash)'],
        [await admin.getAddress(), [capacity, feePercent, metadataIpfsHash]]
      )
    )
    await genesisVault.acceptPoolEscrowOwnership()
    await vaultsRegistry.addVault(proxyAddress)
    await checkVault(genesisVault, genesisImplV3, true)
  })
})
