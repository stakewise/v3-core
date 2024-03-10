import hre, { ethers } from 'hardhat'
import {
  BigNumberish,
  Contract,
  ContractTransactionResponse,
  parseEther,
  Signer,
  Wallet,
} from 'ethers'
import { simulateDeployImpl } from '@openzeppelin/hardhat-upgrades/dist/utils'
import EthereumWallet from 'ethereumjs-wallet'
import {
  BalancerVaultMock,
  BalancerVaultMock__factory,
  ERC20Mock,
  ERC20Mock__factory,
  GnoBlocklistErc20Vault,
  GnoBlocklistErc20Vault__factory,
  GnoBlocklistVault,
  GnoBlocklistVault__factory,
  GnoErc20Vault,
  GnoErc20Vault__factory,
  GnoGenesisVault,
  GnoGenesisVault__factory,
  GnoPrivErc20Vault,
  GnoPrivErc20Vault__factory,
  GnoPrivVault,
  GnoPrivVault__factory,
  GnoSharedMevEscrow,
  GnoVault,
  GnoVault__factory,
  GnoVaultFactory,
  GnoVaultFactory__factory,
  Keeper,
  LegacyRewardTokenMock,
  LegacyRewardTokenMock__factory,
  OsToken,
  OsTokenConfig,
  OsTokenVaultController,
  PoolEscrowMock,
  SharedMevEscrow,
  SharedMevEscrow__factory,
  VaultsRegistry,
  XdaiExchange,
  XdaiExchange__factory,
} from '../../typechain-types'
import { getGnoValidatorsRegistryFactory } from './contracts'
import {
  EXITING_ASSETS_MIN_DELAY,
  MAX_AVG_REWARD_PER_SECOND,
  ORACLES,
  ORACLES_CONFIG,
  OSTOKEN_CAPACITY,
  OSTOKEN_FEE,
  OSTOKEN_LIQ_BONUS,
  OSTOKEN_LIQ_THRESHOLD,
  OSTOKEN_LTV,
  OSTOKEN_NAME,
  OSTOKEN_REDEEM_FROM_LTV,
  OSTOKEN_REDEEM_TO_LTV,
  OSTOKEN_SYMBOL,
  REWARDS_DELAY,
  REWARDS_MIN_ORACLES,
  SECURITY_DEPOSIT,
  VALIDATORS_MIN_ORACLES,
  ZERO_ADDRESS,
  ZERO_BYTES32,
} from './constants'
import { GnoErc20VaultInitParamsStruct, GnoVaultInitParamsStruct, GnoVaultType } from './types'
import {
  extractDepositShares,
  extractExitPositionTicket,
  extractVaultAddress,
  getBlockTimestamp,
  increaseTime,
  setBalance,
} from './utils'
import {
  createKeeper,
  createOsToken,
  createOsTokenConfig,
  createOsTokenVaultController,
  createPoolEscrow,
  createVaultsRegistry,
  transferOwnership,
} from './fixtures'
import { registerEthValidator } from './validators'

export const setGnoWithdrawals = async function (
  validatorsRegistry: Contract,
  gnoToken: ERC20Mock,
  vault: GnoVault | PoolEscrowMock,
  withdrawals: bigint
): Promise<void> {
  const systemAddr = '0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE'
  const system = await ethers.getImpersonatedSigner(systemAddr)
  await setBalance(systemAddr, ethers.parseEther('1'))
  await gnoToken.mint(await validatorsRegistry.getAddress(), withdrawals)
  await validatorsRegistry
    .connect(system)
    .executeSystemWithdrawals(
      [(withdrawals * parseEther('32')) / parseEther('1') / 1000000000n],
      [await vault.getAddress()]
    )
}

export async function collateralizeGnoVault(
  vault: GnoVaultType,
  gnoToken: ERC20Mock,
  keeper: Keeper,
  validatorsRegistry: Contract,
  admin: Wallet
) {
  const adminAddr = await admin.getAddress()

  // register validator
  const validatorDeposit = ethers.parseEther('1')
  const tx = await depositGno(vault, gnoToken, validatorDeposit, admin, admin, ZERO_ADDRESS)
  const receivedShares = await extractDepositShares(tx)
  await registerEthValidator(vault, keeper, validatorsRegistry, admin)

  // exit validator
  const response = await vault.connect(admin).enterExitQueue(receivedShares, adminAddr)
  const positionTicket = await extractExitPositionTicket(response)
  const timestamp = await getBlockTimestamp(response)

  await increaseTime(EXITING_ASSETS_MIN_DELAY)
  await setGnoWithdrawals(validatorsRegistry, gnoToken, vault, validatorDeposit)

  // claim exited assets
  await vault.connect(admin).claimExitedAssets(positionTicket, timestamp, 0)
}

export const depositGno = async function (
  vault: GnoVault,
  gnoToken: ERC20Mock,
  assets: bigint,
  sender: Wallet,
  receiver: Wallet,
  referrer: string
): Promise<ContractTransactionResponse> {
  await gnoToken.mint(await sender.getAddress(), assets)
  await gnoToken.connect(sender).approve(await vault.getAddress(), assets)
  return await vault.connect(sender).deposit(assets, await receiver.getAddress(), referrer)
}

export const createGnoValidatorsRegistry = async function (gnoToken: ERC20Mock): Promise<Contract> {
  const validatorsRegistryFactory = await getGnoValidatorsRegistryFactory()
  const signer = await ethers.provider.getSigner()
  const contract = await validatorsRegistryFactory.deploy(await gnoToken.getAddress())
  return new Contract(await contract.getAddress(), validatorsRegistryFactory.interface, signer)
}

export const approveSecurityDeposit = async function (
  approvedAddr: string,
  gnoToken: ERC20Mock,
  admin: Signer
): Promise<void> {
  await gnoToken.mint(await admin.getAddress(), SECURITY_DEPOSIT)
  await gnoToken.connect(admin).approve(approvedAddr, SECURITY_DEPOSIT)
}

export const createGnoSharedMevEscrow = async function (
  vaultsRegistry: VaultsRegistry
): Promise<SharedMevEscrow> {
  const signer = await ethers.provider.getSigner()
  const factory = await ethers.getContractFactory('GnoSharedMevEscrow')
  const contract = await factory.deploy(await vaultsRegistry.getAddress())
  return SharedMevEscrow__factory.connect(await contract.getAddress(), signer)
}

export const createBalancerVaultMock = async function (
  gnoToken: ERC20Mock,
  daiGnoRate: BigNumberish,
  dao: Signer
): Promise<BalancerVaultMock> {
  const factory = await ethers.getContractFactory('BalancerVaultMock')
  const contract = await factory.deploy(
    await gnoToken.getAddress(),
    daiGnoRate,
    await dao.getAddress()
  )
  return BalancerVaultMock__factory.connect(await contract.getAddress(), dao)
}

export const createXdaiExchange = async function (
  gnoToken: ERC20Mock,
  balancerVault: BalancerVaultMock,
  balancerPoolId: string,
  vaultsRegistry: VaultsRegistry,
  dao: Signer
): Promise<XdaiExchange> {
  const factory = await ethers.getContractFactory('XdaiExchange')

  const constructorArgs = [
    await gnoToken.getAddress(),
    balancerPoolId,
    await balancerVault.getAddress(),
    await vaultsRegistry.getAddress(),
  ]
  const contract = await factory.deploy(...constructorArgs)
  const impl = await contract.getAddress()
  await simulateDeployImpl(hre, factory, { constructorArgs }, impl)

  const proxyFactory = await ethers.getContractFactory('ERC1967Proxy')
  const proxy = await proxyFactory.deploy(impl, '0x')
  const proxyAddress = await proxy.getAddress()
  const xdaiExchange = XdaiExchange__factory.connect(proxyAddress, dao)
  await xdaiExchange.initialize(await dao.getAddress())
  return xdaiExchange
}

export const createGnoVaultFactory = async function (
  implementation: string,
  vaultsRegistry: VaultsRegistry,
  gnoToken: ERC20Mock
): Promise<GnoVaultFactory> {
  const factory = await ethers.getContractFactory('GnoVaultFactory')
  const contract = await factory.deploy(
    implementation,
    await vaultsRegistry.getAddress(),
    await gnoToken.getAddress()
  )
  return GnoVaultFactory__factory.connect(
    await contract.getAddress(),
    await ethers.provider.getSigner()
  )
}

export const deployGnoGenesisVaultImpl = async function (
  keeper: Keeper,
  vaultsRegistry: VaultsRegistry,
  validatorsRegistry: Contract,
  osTokenVaultController: OsTokenVaultController,
  osTokenConfig: OsTokenConfig,
  sharedMevEscrow: SharedMevEscrow,
  gnoToken: ERC20Mock,
  xdaiExchange: XdaiExchange,
  poolEscrow: PoolEscrowMock,
  rewardGnoToken: LegacyRewardTokenMock
): Promise<string> {
  const factory = await ethers.getContractFactory('GnoGenesisVault')
  const constructorArgs = [
    await keeper.getAddress(),
    await vaultsRegistry.getAddress(),
    await validatorsRegistry.getAddress(),
    await osTokenVaultController.getAddress(),
    await osTokenConfig.getAddress(),
    await sharedMevEscrow.getAddress(),
    await gnoToken.getAddress(),
    await xdaiExchange.getAddress(),
    await poolEscrow.getAddress(),
    await rewardGnoToken.getAddress(),
    EXITING_ASSETS_MIN_DELAY,
  ]
  const contract = await factory.deploy(...constructorArgs)
  const vaultImpl = await contract.getAddress()
  await simulateDeployImpl(hre, factory, { constructorArgs }, vaultImpl)
  return vaultImpl
}

export const deployGnoVaultImplementation = async function (
  vaultType: string,
  keeper: Keeper,
  vaultsRegistry: VaultsRegistry,
  validatorsRegistry: string,
  osTokenVaultController: OsTokenVaultController,
  osTokenConfig: OsTokenConfig,
  sharedMevEscrow: GnoSharedMevEscrow,
  gnoToken: ERC20Mock,
  xdaiExchange: XdaiExchange,
  exitingAssetsMinDelay: number
): Promise<string> {
  const factory = await ethers.getContractFactory(vaultType)
  const constructorArgs = [
    await keeper.getAddress(),
    await vaultsRegistry.getAddress(),
    validatorsRegistry,
    await osTokenVaultController.getAddress(),
    await osTokenConfig.getAddress(),
    await sharedMevEscrow.getAddress(),
    await gnoToken.getAddress(),
    await xdaiExchange.getAddress(),
    exitingAssetsMinDelay,
  ]
  const contract = await factory.deploy(...constructorArgs)
  const vaultImpl = await contract.getAddress()
  await simulateDeployImpl(hre, factory, { constructorArgs }, vaultImpl)
  return vaultImpl
}

export const encodeGnoVaultInitParams = function (vaultParams: GnoVaultInitParamsStruct): string {
  return ethers.AbiCoder.defaultAbiCoder().encode(
    ['tuple(uint256 capacity, uint16 feePercent, string metadataIpfsHash)'],
    [[vaultParams.capacity, vaultParams.feePercent, vaultParams.metadataIpfsHash]]
  )
}

export const encodeGnoErc20VaultInitParams = function (
  vaultParams: GnoErc20VaultInitParamsStruct
): string {
  return ethers.AbiCoder.defaultAbiCoder().encode(
    [
      'tuple(uint256 capacity, uint16 feePercent, string name, string symbol, string metadataIpfsHash)',
    ],
    [
      [
        vaultParams.capacity,
        vaultParams.feePercent,
        vaultParams.name,
        vaultParams.symbol,
        vaultParams.metadataIpfsHash,
      ],
    ]
  )
}

interface GnoVaultFixture {
  vaultsRegistry: VaultsRegistry
  keeper: Keeper
  sharedMevEscrow: SharedMevEscrow
  validatorsRegistry: Contract
  gnoVaultFactory: GnoVaultFactory
  gnoPrivVaultFactory: GnoVaultFactory
  gnoErc20VaultFactory: GnoVaultFactory
  gnoPrivErc20VaultFactory: GnoVaultFactory
  gnoBlocklistVaultFactory: GnoVaultFactory
  gnoBlocklistErc20VaultFactory: GnoVaultFactory
  osToken: OsToken
  osTokenVaultController: OsTokenVaultController
  osTokenConfig: OsTokenConfig
  xdaiExchange: XdaiExchange
  gnoToken: ERC20Mock
  balancerVault: BalancerVaultMock

  createGnoVault(
    admin: Signer,
    vaultParams: GnoVaultInitParamsStruct,
    isOwnMevEscrow?: boolean
  ): Promise<GnoVault>

  createGnoPrivVault(
    admin: Signer,
    vaultParams: GnoVaultInitParamsStruct,
    isOwnMevEscrow?: boolean
  ): Promise<GnoPrivVault>

  createGnoBlocklistVault(
    admin: Signer,
    vaultParams: GnoVaultInitParamsStruct,
    isOwnMevEscrow?: boolean
  ): Promise<GnoBlocklistVault>

  createGnoErc20Vault(
    admin: Signer,
    vaultParams: GnoErc20VaultInitParamsStruct,
    isOwnMevEscrow?: boolean
  ): Promise<GnoErc20Vault>

  createGnoPrivErc20Vault(
    admin: Signer,
    vaultParams: GnoErc20VaultInitParamsStruct,
    isOwnMevEscrow?: boolean
  ): Promise<GnoPrivErc20Vault>

  createGnoBlocklistErc20Vault(
    admin: Signer,
    vaultParams: GnoErc20VaultInitParamsStruct,
    isOwnMevEscrow?: boolean
  ): Promise<GnoBlocklistErc20Vault>

  createGnoGenesisVault(
    admin: Signer,
    vaultParams: GnoVaultInitParamsStruct
  ): Promise<[GnoGenesisVault, LegacyRewardTokenMock, PoolEscrowMock]>
}

export const gnoVaultFixture = async function (): Promise<GnoVaultFixture> {
  const dao = await (ethers as any).provider.getSigner()
  const vaultsRegistry = await createVaultsRegistry(true)

  const factory = await ethers.getContractFactory('ERC20Mock')
  const contract = await factory.connect(dao).deploy()
  const gnoToken = ERC20Mock__factory.connect(await contract.getAddress(), dao)
  const validatorsRegistry = await createGnoValidatorsRegistry(gnoToken)

  const sharedMevEscrow = await createGnoSharedMevEscrow(vaultsRegistry)

  // 1. calc osToken address
  const _osTokenAddress = ethers.getCreateAddress({
    from: dao.address,
    nonce: (await ethers.provider.getTransactionCount(dao.address)) + 1,
  })

  // 2. calc keeper address
  const _keeperAddress = ethers.getCreateAddress({
    from: dao.address,
    nonce: (await ethers.provider.getTransactionCount(dao.address)) + 2,
  })

  // 3. deploy osTokenVaultController
  const osTokenVaultController = await createOsTokenVaultController(
    _keeperAddress,
    vaultsRegistry,
    _osTokenAddress,
    dao,
    dao,
    OSTOKEN_FEE,
    OSTOKEN_CAPACITY,
    true
  )

  // 4. deploy osToken
  const osToken = await createOsToken(
    dao,
    osTokenVaultController,
    OSTOKEN_NAME,
    OSTOKEN_SYMBOL,
    true
  )
  if (_osTokenAddress != (await osToken.getAddress())) {
    throw new Error('Invalid calculated OsToken address')
  }

  // 5. deploy keeper
  const sortedOracles = ORACLES.sort((oracle1, oracle2) => {
    const oracle1Addr = new EthereumWallet(oracle1).getAddressString()
    const oracle2Addr = new EthereumWallet(oracle2).getAddressString()
    return oracle1Addr > oracle2Addr ? 1 : -1
  })
  const keeper = await createKeeper(
    sortedOracles.map((s) => new EthereumWallet(s).getAddressString()),
    ORACLES_CONFIG,
    sharedMevEscrow,
    vaultsRegistry,
    osTokenVaultController,
    REWARDS_DELAY,
    MAX_AVG_REWARD_PER_SECOND,
    REWARDS_MIN_ORACLES,
    validatorsRegistry,
    VALIDATORS_MIN_ORACLES,
    true
  )
  if (_keeperAddress != (await keeper.getAddress())) {
    throw new Error('Invalid calculated Keeper address')
  }

  // 6. deploy osTokenConfig
  const osTokenConfig = await createOsTokenConfig(
    dao,
    OSTOKEN_REDEEM_FROM_LTV,
    OSTOKEN_REDEEM_TO_LTV,
    OSTOKEN_LIQ_THRESHOLD,
    OSTOKEN_LIQ_BONUS,
    OSTOKEN_LTV,
    true
  )

  // 7. deploy Balancer vault
  const balancerVault = await createBalancerVaultMock(gnoToken, parseEther('0.003'), dao)

  // 8. deploy XDai exchange
  const xdaiExchange = await createXdaiExchange(
    gnoToken,
    balancerVault,
    ZERO_BYTES32,
    vaultsRegistry,
    dao
  )

  // 9. deploy implementations and factories
  const factories = {}
  const implementations = {}

  for (const vaultType of [
    'GnoVault',
    'GnoPrivVault',
    'GnoErc20Vault',
    'GnoPrivErc20Vault',
    'GnoBlocklistVault',
    'GnoBlocklistErc20Vault',
  ]) {
    const vaultImpl = await deployGnoVaultImplementation(
      vaultType,
      keeper,
      vaultsRegistry,
      await validatorsRegistry.getAddress(),
      osTokenVaultController,
      osTokenConfig,
      sharedMevEscrow,
      gnoToken,
      xdaiExchange,
      EXITING_ASSETS_MIN_DELAY
    )
    await vaultsRegistry.addVaultImpl(vaultImpl)
    implementations[vaultType] = vaultImpl

    const vaultFactory = await createGnoVaultFactory(vaultImpl, vaultsRegistry, gnoToken)
    await vaultsRegistry.addFactory(await vaultFactory.getAddress())
    factories[vaultType] = vaultFactory
  }

  // change ownership
  await transferOwnership(vaultsRegistry, dao)
  await transferOwnership(keeper, dao)

  const gnoVaultFactory = factories['GnoVault']
  const gnoPrivVaultFactory = factories['GnoPrivVault']
  const gnoErc20VaultFactory = factories['GnoErc20Vault']
  const gnoPrivErc20VaultFactory = factories['GnoPrivErc20Vault']
  const gnoBlocklistVaultFactory = factories['GnoBlocklistVault']
  const gnoBlocklistErc20VaultFactory = factories['GnoBlocklistErc20Vault']

  return {
    vaultsRegistry,
    sharedMevEscrow,
    keeper,
    validatorsRegistry,
    gnoVaultFactory,
    gnoPrivVaultFactory,
    gnoErc20VaultFactory,
    gnoPrivErc20VaultFactory,
    gnoBlocklistVaultFactory,
    gnoBlocklistErc20VaultFactory,
    osTokenVaultController,
    osTokenConfig,
    osToken,
    xdaiExchange,
    gnoToken,
    balancerVault,
    createGnoVault: async (
      admin: Signer,
      vaultParams: GnoVaultInitParamsStruct,
      isOwnMevEscrow = false
    ): Promise<GnoVault> => {
      await approveSecurityDeposit(await gnoVaultFactory.getAddress(), gnoToken, admin)
      const tx = await gnoVaultFactory
        .connect(admin)
        .createVault(encodeGnoVaultInitParams(vaultParams), isOwnMevEscrow)
      const vaultAddress = await extractVaultAddress(tx)
      return GnoVault__factory.connect(vaultAddress, await ethers.provider.getSigner())
    },
    createGnoPrivVault: async (
      admin: Signer,
      vaultParams: GnoVaultInitParamsStruct,
      isOwnMevEscrow = false
    ): Promise<GnoPrivVault> => {
      await approveSecurityDeposit(await gnoPrivVaultFactory.getAddress(), gnoToken, admin)
      const tx = await gnoPrivVaultFactory
        .connect(admin)
        .createVault(encodeGnoVaultInitParams(vaultParams), isOwnMevEscrow)
      const vaultAddress = await extractVaultAddress(tx)
      return GnoPrivVault__factory.connect(vaultAddress, await ethers.provider.getSigner())
    },
    createGnoBlocklistVault: async (
      admin: Signer,
      vaultParams: GnoVaultInitParamsStruct,
      isOwnMevEscrow = false
    ): Promise<GnoBlocklistVault> => {
      await approveSecurityDeposit(await gnoBlocklistVaultFactory.getAddress(), gnoToken, admin)
      const tx = await gnoBlocklistVaultFactory
        .connect(admin)
        .createVault(encodeGnoVaultInitParams(vaultParams), isOwnMevEscrow)
      const vaultAddress = await extractVaultAddress(tx)
      return GnoBlocklistVault__factory.connect(vaultAddress, await ethers.provider.getSigner())
    },
    createGnoErc20Vault: async (
      admin: Signer,
      vaultParams: GnoErc20VaultInitParamsStruct,
      isOwnMevEscrow = false
    ): Promise<GnoErc20Vault> => {
      await approveSecurityDeposit(await gnoErc20VaultFactory.getAddress(), gnoToken, admin)
      const tx = await gnoErc20VaultFactory
        .connect(admin)
        .createVault(encodeGnoErc20VaultInitParams(vaultParams), isOwnMevEscrow)
      const vaultAddress = await extractVaultAddress(tx)
      return GnoErc20Vault__factory.connect(vaultAddress, await ethers.provider.getSigner())
    },
    createGnoPrivErc20Vault: async (
      admin: Signer,
      vaultParams: GnoErc20VaultInitParamsStruct,
      isOwnMevEscrow = false
    ): Promise<GnoPrivErc20Vault> => {
      await approveSecurityDeposit(await gnoPrivErc20VaultFactory.getAddress(), gnoToken, admin)
      const tx = await gnoPrivErc20VaultFactory
        .connect(admin)
        .createVault(encodeGnoErc20VaultInitParams(vaultParams), isOwnMevEscrow)
      const vaultAddress = await extractVaultAddress(tx)
      return GnoPrivErc20Vault__factory.connect(vaultAddress, await ethers.provider.getSigner())
    },
    createGnoBlocklistErc20Vault: async (
      admin: Wallet,
      vaultParams: GnoErc20VaultInitParamsStruct,
      isOwnMevEscrow = false
    ): Promise<GnoBlocklistErc20Vault> => {
      await approveSecurityDeposit(
        await gnoBlocklistErc20VaultFactory.getAddress(),
        gnoToken,
        admin
      )
      const tx = await gnoBlocklistErc20VaultFactory
        .connect(admin)
        .createVault(encodeGnoErc20VaultInitParams(vaultParams), isOwnMevEscrow)
      const vaultAddress = await extractVaultAddress(tx)
      return GnoBlocklistErc20Vault__factory.connect(
        vaultAddress,
        await ethers.provider.getSigner()
      )
    },
    createGnoGenesisVault: async (
      admin: Signer,
      vaultParams: GnoVaultInitParamsStruct
    ): Promise<[GnoGenesisVault, LegacyRewardTokenMock, PoolEscrowMock]> => {
      const poolEscrow = await createPoolEscrow(dao.address, true)
      const legacyRewardTokenMockFactory = await ethers.getContractFactory('LegacyRewardTokenMock')
      const legacyRewardTokenMock = await legacyRewardTokenMockFactory.deploy()
      const rewardGnoToken = LegacyRewardTokenMock__factory.connect(
        await legacyRewardTokenMock.getAddress(),
        dao
      )

      const vaultImpl = await deployGnoGenesisVaultImpl(
        keeper,
        vaultsRegistry,
        validatorsRegistry,
        osTokenVaultController,
        osTokenConfig,
        sharedMevEscrow,
        gnoToken,
        xdaiExchange,
        poolEscrow,
        rewardGnoToken
      )
      await vaultsRegistry.addVaultImpl(vaultImpl)

      const proxyFactory = await ethers.getContractFactory('ERC1967Proxy')
      const proxy = await proxyFactory.deploy(vaultImpl, '0x')
      const proxyAddress = await proxy.getAddress()
      const vault = GnoGenesisVault__factory.connect(
        proxyAddress,
        await ethers.provider.getSigner()
      )
      await rewardGnoToken.connect(dao).setVault(proxyAddress)
      await poolEscrow.connect(dao).commitOwnershipTransfer(proxyAddress)
      const adminAddr = await admin.getAddress()
      await approveSecurityDeposit(await vault.getAddress(), gnoToken, admin)

      await vault
        .connect(admin)
        .initialize(
          ethers.AbiCoder.defaultAbiCoder().encode(
            ['address', 'tuple(uint256 capacity, uint16 feePercent, string metadataIpfsHash)'],
            [
              adminAddr,
              [vaultParams.capacity, vaultParams.feePercent, vaultParams.metadataIpfsHash],
            ]
          )
        )
      await vaultsRegistry.addVault(proxyAddress)
      return [vault, rewardGnoToken, poolEscrow]
    },
  }
}
