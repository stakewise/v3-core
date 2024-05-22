import hre, { ethers } from 'hardhat'
import { BigNumberish, Contract, ContractFactory, parseEther, Signer, Wallet } from 'ethers'
import { simulateDeployImpl } from '@openzeppelin/hardhat-upgrades/dist/utils'
import {
  impersonateAccount,
  stopImpersonatingAccount,
} from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { signTypedData, SignTypedDataVersion } from '@metamask/eth-sig-util'
import EthereumWallet from 'ethereumjs-wallet'
import {
  CumulativeMerkleDrop,
  CumulativeMerkleDrop__factory,
  EthBlocklistErc20Vault,
  EthBlocklistErc20Vault__factory,
  EthBlocklistVault,
  EthBlocklistVault__factory,
  EthErc20Vault,
  EthErc20Vault__factory,
  EthFoxVault,
  EthFoxVault__factory,
  EthGenesisVault,
  EthGenesisVault__factory,
  EthPrivErc20Vault,
  EthPrivErc20Vault__factory,
  EthPrivVault,
  EthPrivVault__factory,
  EthVault,
  EthVault__factory,
  EthVaultFactory,
  EthVaultFactory__factory,
  EthVaultMock,
  EthVaultMock__factory,
  IKeeperRewards,
  Keeper,
  Keeper__factory,
  LegacyRewardTokenMock,
  LegacyRewardTokenMock__factory,
  OsToken,
  OsToken__factory,
  OsTokenConfig,
  OsTokenConfig__factory,
  OsTokenVaultController,
  OsTokenVaultController__factory,
  PoolEscrowMock,
  PoolEscrowMock__factory,
  PriceFeed,
  PriceFeed__factory,
  RewardSplitterFactory,
  RewardSplitterFactory__factory,
  SharedMevEscrow,
  SharedMevEscrow__factory,
  VaultsRegistry,
  VaultsRegistry__factory,
  DepositDataRegistry,
  DepositDataRegistry__factory,
  EthValidatorsChecker__factory,
} from '../../typechain-types'
import { getEthValidatorsRegistryFactory, getOsTokenConfigV1Factory } from './contracts'
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
  OSTOKEN_SYMBOL,
  REWARDS_DELAY,
  REWARDS_MIN_ORACLES,
  SECURITY_DEPOSIT,
  VALIDATORS_MIN_ORACLES,
} from './constants'
import {
  EthErc20VaultInitParamsStruct,
  EthRestakeVaultType,
  EthVaultInitParamsStruct,
  EthVaultType,
} from './types'
import { DepositorMock } from '../../typechain-types/contracts/mocks/DepositorMock'
import { DepositorMock__factory } from '../../typechain-types/factories/contracts/mocks/DepositorMock__factory'
import { UnknownVaultMock } from '../../typechain-types/contracts/mocks/UnknownVaultMock'
import { UnknownVaultMock__factory } from '../../typechain-types/factories/contracts/mocks/UnknownVaultMock__factory'
import { MulticallMock__factory } from '../../typechain-types/factories/contracts/mocks/MulticallMock__factory'
import { MulticallMock } from '../../typechain-types/contracts/mocks/MulticallMock'
import { extractVaultAddress, setBalance } from './utils'
import { MAINNET_FORK, NETWORKS } from '../../helpers/constants'
import mainnetDeployment from '../../deployments/mainnet.json'

export const transferOwnership = async function (
  contract:
    | Keeper
    | VaultsRegistry
    | OsTokenVaultController
    | OsToken
    | OsTokenConfig
    | CumulativeMerkleDrop,
  newOwner: Signer
) {
  const currentOwnerAddr = await contract.owner()
  const newOwnerAddr = await newOwner.getAddress()
  if (currentOwnerAddr == newOwnerAddr) return

  await impersonateAccount(currentOwnerAddr)
  const currentOwner = await ethers.provider.getSigner(currentOwnerAddr)

  await setBalance(currentOwnerAddr, ethers.parseEther('100'))
  await contract.connect(currentOwner).transferOwnership(newOwnerAddr)
  await stopImpersonatingAccount(currentOwnerAddr)

  await contract.connect(newOwner).acceptOwnership()
}

export const upgradeVault = async function (
  vault: EthVaultType,
  implementation: string
): Promise<EthVaultType> {
  const adminAddr = await vault.admin()
  const admin = await ethers.getImpersonatedSigner(adminAddr)
  await setBalance(adminAddr, ethers.parseEther('1'))
  await vault.connect(admin).upgradeToAndCall(implementation, '0x')
  return vault
}

export const updateVaultState = async function (
  keeper: Keeper,
  vault: EthVaultType,
  harvestParams: IKeeperRewards.HarvestParamsStruct
) {
  if (!(await keeper.canHarvest(await vault.getAddress()))) {
    return
  }
  await vault.updateState(harvestParams)
}

export const createDepositorMock = async function (
  vault: EthVaultType | EthRestakeVaultType
): Promise<DepositorMock> {
  const depositorMockFactory = await ethers.getContractFactory('DepositorMock')
  const contract = await depositorMockFactory.deploy(await vault.getAddress())
  return DepositorMock__factory.connect(
    await contract.getAddress(),
    await ethers.provider.getSigner()
  )
}

export const createUnknownVaultMock = async function (
  osTokenVaultController: OsTokenVaultController,
  implementation: string
): Promise<UnknownVaultMock> {
  const factory = await ethers.getContractFactory('UnknownVaultMock')
  const contract = await factory.deploy(await osTokenVaultController.getAddress(), implementation)
  return UnknownVaultMock__factory.connect(
    await contract.getAddress(),
    await ethers.provider.getSigner()
  )
}

export const createMulticallMock = async function (): Promise<MulticallMock> {
  const contract = await ethers.deployContract('MulticallMock')
  return MulticallMock__factory.connect(
    await contract.getAddress(),
    await ethers.provider.getSigner()
  )
}
export const createEthValidatorsRegistry = async function (): Promise<Contract> {
  const validatorsRegistryFactory = await getEthValidatorsRegistryFactory()
  const signer = await ethers.provider.getSigner()

  if (MAINNET_FORK.enabled) {
    return new Contract(
      NETWORKS.mainnet.validatorsRegistry,
      validatorsRegistryFactory.interface,
      signer
    )
  }
  const contract = await validatorsRegistryFactory.deploy()
  return new Contract(await contract.getAddress(), validatorsRegistryFactory.interface, signer)
}

export const createPoolEscrow = async function (
  stakedEthTokenAddress: string,
  skipFork: boolean = false
): Promise<PoolEscrowMock> {
  const signer = await ethers.provider.getSigner()

  if (MAINNET_FORK.enabled && !skipFork) {
    return PoolEscrowMock__factory.connect(NETWORKS.mainnet.genesisVault.poolEscrow, signer)
  }
  const factory = await ethers.getContractFactory('PoolEscrowMock')
  const contract = await factory.deploy(stakedEthTokenAddress)
  return PoolEscrowMock__factory.connect(await contract.getAddress(), signer)
}

export const createVaultsRegistry = async function (
  skipFork: boolean = false
): Promise<VaultsRegistry> {
  const signer = await ethers.provider.getSigner()

  if (MAINNET_FORK.enabled && !skipFork) {
    const contract = VaultsRegistry__factory.connect(mainnetDeployment.VaultsRegistry, signer)
    await transferOwnership(contract, signer)
    return contract
  }
  const factory = await ethers.getContractFactory('VaultsRegistry')
  const contract = await factory.deploy()
  const registry = VaultsRegistry__factory.connect(await contract.getAddress(), signer)
  await registry.initialize(signer.address)
  return registry
}

export const createEthSharedMevEscrow = async function (
  vaultsRegistry: VaultsRegistry
): Promise<SharedMevEscrow> {
  const signer = await ethers.provider.getSigner()
  if (MAINNET_FORK.enabled) {
    return SharedMevEscrow__factory.connect(mainnetDeployment.SharedMevEscrow, signer)
  }
  const factory = await ethers.getContractFactory('SharedMevEscrow')
  const contract = await factory.deploy(await vaultsRegistry.getAddress())
  return SharedMevEscrow__factory.connect(await contract.getAddress(), signer)
}

export const createPriceFeed = async function (
  osTokenVaultController: OsTokenVaultController,
  description: string
): Promise<PriceFeed> {
  const signer = await ethers.provider.getSigner()
  if (MAINNET_FORK.enabled) {
    return PriceFeed__factory.connect(mainnetDeployment.PriceFeed, signer)
  }
  const factory = await ethers.getContractFactory('PriceFeed')
  const contract = await factory.deploy(await osTokenVaultController.getAddress(), description)
  return PriceFeed__factory.connect(await contract.getAddress(), signer)
}

export const createRewardSplitterFactory = async function (): Promise<RewardSplitterFactory> {
  const signer = await ethers.provider.getSigner()
  if (MAINNET_FORK.enabled) {
    return RewardSplitterFactory__factory.connect(mainnetDeployment.RewardSplitterFactory, signer)
  }
  let factory = await ethers.getContractFactory('RewardSplitter')
  const rewardSplitterImpl = await factory.deploy()

  factory = await ethers.getContractFactory('RewardSplitterFactory')
  const contract = await factory.deploy(await rewardSplitterImpl.getAddress())
  return RewardSplitterFactory__factory.connect(await contract.getAddress(), signer)
}

export const createDepositDataRegistry = async function (
  vaultsRegistry: VaultsRegistry
): Promise<DepositDataRegistry> {
  const signer = await ethers.provider.getSigner()
  const factory = await ethers.getContractFactory('DepositDataRegistry')
  const contract = await factory.deploy(await vaultsRegistry.getAddress())
  return DepositDataRegistry__factory.connect(await contract.getAddress(), signer)
}

export const createEthValidatorsChecker = async function (
  validatorsRegistry: Contract,
  keeper: Keeper,
  vaultsRegistry: VaultsRegistry,
  depositDataRegistry: DepositDataRegistry
) {
  const signer = await ethers.provider.getSigner()
  const factory = await ethers.getContractFactory('EthValidatorsChecker')
  const contract = await factory.deploy(
    await validatorsRegistry.getAddress(),
    await keeper.getAddress(),
    await vaultsRegistry.getAddress(),
    await depositDataRegistry.getAddress()
  )
  return EthValidatorsChecker__factory.connect(await contract.getAddress(), signer)
}

export const createOsTokenVaultController = async function (
  keeperAddress: string,
  registry: VaultsRegistry,
  osTokenAddress: string,
  treasury: Wallet,
  governor: Wallet,
  feePercent: BigNumberish,
  capacity: BigNumberish,
  skipFork: boolean = false
): Promise<OsTokenVaultController> {
  const signer = await ethers.provider.getSigner()
  if (MAINNET_FORK.enabled && !skipFork) {
    const contract = OsTokenVaultController__factory.connect(
      mainnetDeployment.OsTokenVaultController,
      signer
    )
    await transferOwnership(contract, governor)
    await contract.connect(governor).setTreasury(treasury.address)
    return contract
  }
  const factory = await ethers.getContractFactory('OsTokenVaultController')
  const contract = await factory.deploy(
    keeperAddress,
    await registry.getAddress(),
    osTokenAddress,
    treasury.address,
    governor.address,
    feePercent,
    capacity
  )
  return OsTokenVaultController__factory.connect(await contract.getAddress(), signer)
}

export const createOsToken = async function (
  governor: Wallet,
  vaultController: OsTokenVaultController,
  name: string,
  symbol: string,
  skipFork: boolean = false
): Promise<OsToken> {
  const signer = await ethers.provider.getSigner()
  if (MAINNET_FORK.enabled && !skipFork) {
    const contract = OsToken__factory.connect(mainnetDeployment.OsToken, signer)
    await transferOwnership(contract, governor)
    return contract
  }
  const factory = await ethers.getContractFactory('OsToken')
  const contract = await factory.deploy(
    governor.address,
    await vaultController.getAddress(),
    name,
    symbol
  )
  return OsToken__factory.connect(await contract.getAddress(), signer)
}

export const createOsTokenConfig = async function (
  owner: Wallet,
  liqThresholdPercent: BigNumberish,
  liqBonusPercent: BigNumberish,
  ltvPercent: BigNumberish,
  redeemer: Wallet
): Promise<OsTokenConfig> {
  const signer = await ethers.provider.getSigner()
  const factory = await ethers.getContractFactory('OsTokenConfig')
  const contract = await factory.deploy(
    owner.address,
    {
      liqBonusPercent,
      liqThresholdPercent,
      ltvPercent,
    },
    await redeemer.getAddress()
  )
  return OsTokenConfig__factory.connect(await contract.getAddress(), signer)
}

export const createCumulativeMerkleDrop = async function (
  token: string,
  owner: Wallet
): Promise<CumulativeMerkleDrop> {
  const factory = await ethers.getContractFactory('CumulativeMerkleDrop')
  const contract = await factory.deploy(owner.address, token)
  return CumulativeMerkleDrop__factory.connect(
    await contract.getAddress(),
    await ethers.provider.getSigner()
  )
}

export const createKeeper = async function (
  initialOracles: string[],
  configIpfsHash: string,
  sharedMevEscrow: SharedMevEscrow,
  vaultsRegistry: VaultsRegistry,
  osTokenVaultController: OsTokenVaultController,
  rewardsDelay: BigNumberish,
  maxAvgRewardPerSecond: BigNumberish,
  rewardsMinOracles: BigNumberish,
  validatorsRegistry: Contract,
  validatorsMinOracles: BigNumberish,
  skipFork: boolean = false
): Promise<Keeper> {
  const signer = await ethers.provider.getSigner()
  let keeper: Keeper
  if (MAINNET_FORK.enabled && !skipFork) {
    keeper = Keeper__factory.connect(mainnetDeployment.Keeper, signer)
  } else {
    const factory = await ethers.getContractFactory('Keeper')
    const contract = await factory.deploy(
      await sharedMevEscrow.getAddress(),
      await vaultsRegistry.getAddress(),
      await osTokenVaultController.getAddress(),
      rewardsDelay,
      maxAvgRewardPerSecond,
      await validatorsRegistry.getAddress()
    )
    keeper = Keeper__factory.connect(await contract.getAddress(), signer)
    await keeper.connect(signer).initialize(signer.address)
  }

  if (MAINNET_FORK.enabled && !skipFork) {
    // transfer dao ownership
    await transferOwnership(keeper, signer)

    // drop mainnet oracles
    for (const oracleAddr of MAINNET_FORK.oracles) {
      await keeper.removeOracle(oracleAddr)
    }
  }

  for (let i = 0; i < initialOracles.length; i++) {
    await keeper.addOracle(initialOracles[i])
  }

  await keeper.updateConfig(configIpfsHash)
  await keeper.setRewardsMinOracles(rewardsMinOracles)
  await keeper.setValidatorsMinOracles(validatorsMinOracles)
  return keeper
}

export const createEthVaultFactory = async function (
  implementation: string,
  vaultsRegistry: VaultsRegistry
): Promise<EthVaultFactory> {
  const factory = await ethers.getContractFactory('EthVaultFactory')
  const contract = await factory.deploy(implementation, await vaultsRegistry.getAddress())
  return EthVaultFactory__factory.connect(
    await contract.getAddress(),
    await ethers.provider.getSigner()
  )
}

export const deployEthGenesisVaultImpl = async function (
  keeper: Keeper,
  vaultsRegistry: VaultsRegistry,
  validatorsRegistry: Contract,
  osTokenVaultController: OsTokenVaultController,
  osTokenConfig: OsTokenConfig,
  sharedMevEscrow: SharedMevEscrow,
  depositDataRegistry: DepositDataRegistry,
  poolEscrow: PoolEscrowMock,
  rewardEthToken: LegacyRewardTokenMock
): Promise<string> {
  const factory = await ethers.getContractFactory('EthGenesisVault')
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
  const vaultImpl = await contract.getAddress()
  await simulateDeployImpl(hre, factory, { constructorArgs }, vaultImpl)
  return vaultImpl
}

export const deployEthVaultImplementation = async function (
  vaultType: string,
  keeper: Keeper,
  vaultsRegistry: VaultsRegistry,
  validatorsRegistry: string,
  osTokenVaultController: OsTokenVaultController,
  osTokenConfig: OsTokenConfig,
  sharedMevEscrow: SharedMevEscrow,
  depositDataRegistry: DepositDataRegistry,
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
    await depositDataRegistry.getAddress(),
    exitingAssetsMinDelay,
  ]
  const contract = await factory.deploy(...constructorArgs)
  const vaultImpl = await contract.getAddress()
  await simulateDeployImpl(hre, factory, { constructorArgs }, vaultImpl)
  return vaultImpl
}

export async function deployOsTokenConfigV1(dao: Signer): Promise<Contract> {
  const factory = await getOsTokenConfigV1Factory()
  const contract = await factory.deploy(await dao.getAddress(), {
    redeemFromLtvPercent: 9150,
    redeemToLtvPercent: 9000,
    liqBonusPercent: 10100,
    liqThresholdPercent: 9200,
    ltvPercent: 9000,
  })
  return new Contract(await contract.getAddress(), factory.interface, dao)
}

export async function deployEthVaultV1(
  implFactory: ContractFactory,
  admin: Signer,
  keeper: Keeper,
  vaultsRegistry: VaultsRegistry,
  validatorsRegistry: Contract,
  osTokenVaultController: OsTokenVaultController,
  osTokenConfig: Contract,
  sharedMevEscrow: SharedMevEscrow,
  encodedParams: string,
  isOwnMevEscrow = false
): Promise<Contract> {
  const constructorArgs = [
    await keeper.getAddress(),
    await vaultsRegistry.getAddress(),
    await validatorsRegistry.getAddress(),
    await osTokenVaultController.getAddress(),
    await osTokenConfig.getAddress(),
    await sharedMevEscrow.getAddress(),
    EXITING_ASSETS_MIN_DELAY,
  ]
  const vaultImpl = await implFactory.deploy(...constructorArgs)
  const vaultImplAddr = await vaultImpl.getAddress()
  await vaultsRegistry.addVaultImpl(vaultImplAddr)

  const vaultFactory = await createEthVaultFactory(vaultImplAddr, vaultsRegistry)
  await vaultsRegistry.addFactory(await vaultFactory.getAddress())

  const tx = await vaultFactory.connect(admin).createVault(encodedParams, isOwnMevEscrow, {
    value: SECURITY_DEPOSIT,
  })
  return new Contract(
    await extractVaultAddress(tx),
    implFactory.interface,
    await ethers.provider.getSigner()
  )
}

export const encodeEthVaultInitParams = function (vaultParams: EthVaultInitParamsStruct): string {
  return ethers.AbiCoder.defaultAbiCoder().encode(
    ['tuple(uint256 capacity, uint16 feePercent, string metadataIpfsHash)'],
    [[vaultParams.capacity, vaultParams.feePercent, vaultParams.metadataIpfsHash]]
  )
}

export const encodeEthErc20VaultInitParams = function (
  vaultParams: EthErc20VaultInitParamsStruct
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

export const getOraclesSignatures = function (
  typedData: any,
  count: number = REWARDS_MIN_ORACLES
): Buffer {
  const sortedOracles = ORACLES.sort((oracle1, oracle2) => {
    const oracle1Addr = new EthereumWallet(oracle1).getAddressString()
    const oracle2Addr = new EthereumWallet(oracle2).getAddressString()
    return oracle1Addr > oracle2Addr ? 1 : -1
  })
  const signatures: Buffer[] = []
  for (let i = 0; i < count; i++) {
    signatures.push(
      Buffer.from(
        ethers.getBytes(
          signTypedData({
            privateKey: sortedOracles[i],
            data: typedData,
            version: SignTypedDataVersion.V4,
          })
        )
      )
    )
  }
  return Buffer.concat(signatures)
}

interface EthVaultFixture {
  vaultsRegistry: VaultsRegistry
  keeper: Keeper
  sharedMevEscrow: SharedMevEscrow
  depositDataRegistry: DepositDataRegistry
  validatorsRegistry: Contract
  ethVaultFactory: EthVaultFactory
  ethPrivVaultFactory: EthVaultFactory
  ethErc20VaultFactory: EthVaultFactory
  ethPrivErc20VaultFactory: EthVaultFactory
  ethBlocklistVaultFactory: EthVaultFactory
  ethBlocklistErc20VaultFactory: EthVaultFactory
  osToken: OsToken
  osTokenVaultController: OsTokenVaultController
  osTokenConfig: OsTokenConfig

  createEthVault(
    admin: Signer,
    vaultParams: EthVaultInitParamsStruct,
    isOwnMevEscrow?: boolean,
    skipFork?: boolean
  ): Promise<EthVault>

  createEthFoxVault(admin: Signer, vaultParams: EthVaultInitParamsStruct): Promise<EthFoxVault>

  createEthVaultMock(
    admin: Signer,
    vaultParams: EthVaultInitParamsStruct,
    isOwnMevEscrow?: boolean
  ): Promise<EthVaultMock>

  createEthPrivVault(
    admin: Signer,
    vaultParams: EthVaultInitParamsStruct,
    isOwnMevEscrow?: boolean
  ): Promise<EthPrivVault>

  createEthBlocklistVault(
    admin: Signer,
    vaultParams: EthVaultInitParamsStruct,
    isOwnMevEscrow?: boolean
  ): Promise<EthBlocklistVault>

  createEthErc20Vault(
    admin: Signer,
    vaultParams: EthErc20VaultInitParamsStruct,
    isOwnMevEscrow?: boolean,
    skipFork?: boolean
  ): Promise<EthErc20Vault>

  createEthPrivErc20Vault(
    admin: Signer,
    vaultParams: EthErc20VaultInitParamsStruct,
    isOwnMevEscrow?: boolean
  ): Promise<EthPrivErc20Vault>

  createEthBlocklistErc20Vault(
    admin: Signer,
    vaultParams: EthErc20VaultInitParamsStruct,
    isOwnMevEscrow?: boolean
  ): Promise<EthBlocklistErc20Vault>

  createEthGenesisVault(
    admin: Signer,
    vaultParams: EthVaultInitParamsStruct,
    skipFork?: boolean
  ): Promise<[EthGenesisVault, LegacyRewardTokenMock, PoolEscrowMock]>
}

export type { EthVaultFixture }

export const ethVaultFixture = async function (): Promise<EthVaultFixture> {
  const dao = await (ethers as any).provider.getSigner()
  const vaultsRegistry = await createVaultsRegistry()
  const validatorsRegistry = await createEthValidatorsRegistry()

  const sharedMevEscrow = await createEthSharedMevEscrow(vaultsRegistry)

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
    OSTOKEN_CAPACITY
  )

  // 4. deploy osToken
  const osToken = await createOsToken(dao, osTokenVaultController, OSTOKEN_NAME, OSTOKEN_SYMBOL)
  if (!MAINNET_FORK.enabled && _osTokenAddress != (await osToken.getAddress())) {
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
    VALIDATORS_MIN_ORACLES
  )
  if (!MAINNET_FORK.enabled && _keeperAddress != (await keeper.getAddress())) {
    throw new Error('Invalid calculated Keeper address')
  }

  // 6. deploy osTokenConfig
  const osTokenConfig = await createOsTokenConfig(
    dao,
    OSTOKEN_LIQ_THRESHOLD,
    OSTOKEN_LIQ_BONUS,
    OSTOKEN_LTV,
    dao
  )

  // 7. deploy depositDataRegistry
  const depositDataRegistry = await createDepositDataRegistry(vaultsRegistry)

  // 8. deploy implementations and factories
  const factories = {}
  const implementations = {}

  for (const vaultType of [
    'EthVault',
    'EthPrivVault',
    'EthErc20Vault',
    'EthPrivErc20Vault',
    'EthBlocklistVault',
    'EthBlocklistErc20Vault',
    'EthVaultMock',
  ]) {
    const vaultImpl = await deployEthVaultImplementation(
      vaultType,
      keeper,
      vaultsRegistry,
      await validatorsRegistry.getAddress(),
      osTokenVaultController,
      osTokenConfig,
      sharedMevEscrow,
      depositDataRegistry,
      EXITING_ASSETS_MIN_DELAY
    )
    await vaultsRegistry.addVaultImpl(vaultImpl)
    implementations[vaultType] = vaultImpl

    const vaultFactory = await createEthVaultFactory(vaultImpl, vaultsRegistry)
    await vaultsRegistry.addFactory(await vaultFactory.getAddress())
    factories[vaultType] = vaultFactory
  }

  // change ownership
  await transferOwnership(vaultsRegistry, dao)
  await transferOwnership(keeper, dao)

  const ethVaultFactory = factories['EthVault']
  const ethPrivVaultFactory = factories['EthPrivVault']
  const ethErc20VaultFactory = factories['EthErc20Vault']
  const ethPrivErc20VaultFactory = factories['EthPrivErc20Vault']
  const ethBlocklistVaultFactory = factories['EthBlocklistVault']
  const ethBlocklistErc20VaultFactory = factories['EthBlocklistErc20Vault']

  return {
    vaultsRegistry,
    sharedMevEscrow,
    depositDataRegistry,
    keeper,
    validatorsRegistry,
    ethVaultFactory,
    ethPrivVaultFactory,
    ethErc20VaultFactory,
    ethPrivErc20VaultFactory,
    ethBlocklistVaultFactory,
    ethBlocklistErc20VaultFactory,
    osTokenVaultController,
    osTokenConfig,
    osToken,
    createEthVault: async (
      admin: Signer,
      vaultParams: EthVaultInitParamsStruct,
      isOwnMevEscrow = false,
      skipFork = false
    ): Promise<EthVault> => {
      let vaultAddress: string
      if (!MAINNET_FORK.enabled || skipFork) {
        const tx = await ethVaultFactory
          .connect(admin)
          .createVault(encodeEthVaultInitParams(vaultParams), isOwnMevEscrow, {
            value: SECURITY_DEPOSIT,
          })
        vaultAddress = await extractVaultAddress(tx)
        return EthVault__factory.connect(vaultAddress, await ethers.provider.getSigner())
      } else if (isOwnMevEscrow) {
        vaultAddress = MAINNET_FORK.vaults.ethVaultOwnMevEscrow
      } else {
        vaultAddress = MAINNET_FORK.vaults.ethVaultSharedMevEscrow
      }
      const vault = EthVault__factory.connect(vaultAddress, await ethers.provider.getSigner())
      await upgradeVault(vault, implementations['EthVault'])
      await updateVaultState(keeper, vault, MAINNET_FORK.harvestParams[vaultAddress])
      await setBalance(await vault.admin(), parseEther('1000'))
      return vault
    },
    createEthFoxVault: async (
      admin: Signer,
      vaultParams: EthVaultInitParamsStruct
    ): Promise<EthFoxVault> => {
      const factory = await ethers.getContractFactory('EthFoxVault')
      const constructorArgs = [
        await keeper.getAddress(),
        await vaultsRegistry.getAddress(),
        await validatorsRegistry.getAddress(),
        await sharedMevEscrow.getAddress(),
        await depositDataRegistry.getAddress(),
        EXITING_ASSETS_MIN_DELAY,
      ]
      const contract = await factory.deploy(...constructorArgs)
      const vaultImpl = await contract.getAddress()
      await simulateDeployImpl(hre, factory, { constructorArgs }, vaultImpl)

      const proxyFactory = await ethers.getContractFactory('ERC1967Proxy')
      const proxy = await proxyFactory.deploy(vaultImpl, '0x')
      const vault = EthFoxVault__factory.connect(
        await proxy.getAddress(),
        await ethers.provider.getSigner()
      )
      const adminAddr = await admin.getAddress()

      const ownMevEscrowFactory = await ethers.getContractFactory('OwnMevEscrow')
      const ownMevEscrow = await ownMevEscrowFactory.deploy(await vault.getAddress())

      await vault.initialize(
        ethers.AbiCoder.defaultAbiCoder().encode(
          [
            'tuple(address admin, address ownMevEscrow, uint256 capacity, uint16 feePercent, string metadataIpfsHash)',
          ],
          [
            [
              adminAddr,
              await ownMevEscrow.getAddress(),
              vaultParams.capacity,
              vaultParams.feePercent,
              vaultParams.metadataIpfsHash,
            ],
          ]
        ),
        { value: SECURITY_DEPOSIT }
      )
      await vaultsRegistry.addVault(await proxy.getAddress())
      return vault
    },
    createEthVaultMock: async (
      admin: Signer,
      vaultParams: EthVaultInitParamsStruct,
      isOwnMevEscrow = false
    ): Promise<EthVaultMock> => {
      const tx = await factories['EthVaultMock']
        .connect(admin)
        .createVault(encodeEthVaultInitParams(vaultParams), isOwnMevEscrow, {
          value: SECURITY_DEPOSIT,
        })
      const vaultAddress = await extractVaultAddress(tx)
      return EthVaultMock__factory.connect(vaultAddress, await ethers.provider.getSigner())
    },
    createEthPrivVault: async (
      admin: Signer,
      vaultParams: EthVaultInitParamsStruct,
      isOwnMevEscrow = false
    ): Promise<EthPrivVault> => {
      let vaultAddress: string
      if (!MAINNET_FORK.enabled) {
        const tx = await ethPrivVaultFactory
          .connect(admin)
          .createVault(encodeEthVaultInitParams(vaultParams), isOwnMevEscrow, {
            value: SECURITY_DEPOSIT,
          })
        vaultAddress = await extractVaultAddress(tx)
        return EthPrivVault__factory.connect(vaultAddress, await ethers.provider.getSigner())
      } else if (isOwnMevEscrow) {
        vaultAddress = MAINNET_FORK.vaults.ethPrivVaultOwnMevEscrow
      } else {
        vaultAddress = MAINNET_FORK.vaults.ethPrivVaultSharedMevEscrow
      }
      const vault = EthPrivVault__factory.connect(vaultAddress, await ethers.provider.getSigner())
      await upgradeVault(vault, implementations['EthPrivVault'])
      await updateVaultState(keeper, vault, MAINNET_FORK.harvestParams[vaultAddress])
      await setBalance(await vault.admin(), parseEther('1000'))
      return vault
    },
    createEthBlocklistVault: async (
      admin: Signer,
      vaultParams: EthVaultInitParamsStruct,
      isOwnMevEscrow = false
    ): Promise<EthBlocklistVault> => {
      const tx = await ethBlocklistVaultFactory
        .connect(admin)
        .createVault(encodeEthVaultInitParams(vaultParams), isOwnMevEscrow, {
          value: SECURITY_DEPOSIT,
        })
      const vaultAddress = await extractVaultAddress(tx)
      return EthBlocklistVault__factory.connect(vaultAddress, await ethers.provider.getSigner())
    },
    createEthErc20Vault: async (
      admin: Signer,
      vaultParams: EthErc20VaultInitParamsStruct,
      isOwnMevEscrow = false,
      skipFork = false
    ): Promise<EthErc20Vault> => {
      let vaultAddress: string
      if (!MAINNET_FORK.enabled || skipFork) {
        const tx = await ethErc20VaultFactory
          .connect(admin)
          .createVault(encodeEthErc20VaultInitParams(vaultParams), isOwnMevEscrow, {
            value: SECURITY_DEPOSIT,
          })
        vaultAddress = await extractVaultAddress(tx)
        return EthErc20Vault__factory.connect(vaultAddress, await ethers.provider.getSigner())
      } else if (isOwnMevEscrow) {
        vaultAddress = MAINNET_FORK.vaults.ethErc20VaultOwnMevEscrow
      } else {
        vaultAddress = MAINNET_FORK.vaults.ethErc20VaultSharedMevEscrow
      }
      const vault = EthErc20Vault__factory.connect(vaultAddress, await ethers.provider.getSigner())
      await upgradeVault(vault, implementations['EthErc20Vault'])
      await updateVaultState(keeper, vault, MAINNET_FORK.harvestParams[vaultAddress])
      await setBalance(await vault.admin(), parseEther('1000'))
      return vault
    },
    createEthPrivErc20Vault: async (
      admin: Signer,
      vaultParams: EthErc20VaultInitParamsStruct,
      isOwnMevEscrow = false
    ): Promise<EthPrivErc20Vault> => {
      let vaultAddress: string
      if (!MAINNET_FORK.enabled) {
        const tx = await ethPrivErc20VaultFactory
          .connect(admin)
          .createVault(encodeEthErc20VaultInitParams(vaultParams), isOwnMevEscrow, {
            value: SECURITY_DEPOSIT,
          })
        vaultAddress = await extractVaultAddress(tx)
        return EthPrivErc20Vault__factory.connect(vaultAddress, await ethers.provider.getSigner())
      } else if (isOwnMevEscrow) {
        vaultAddress = MAINNET_FORK.vaults.ethPrivErc20VaultOwnMevEscrow
      } else {
        vaultAddress = MAINNET_FORK.vaults.ethPrivErc20VaultSharedMevEscrow
      }
      const vault = EthPrivErc20Vault__factory.connect(
        vaultAddress,
        await ethers.provider.getSigner()
      )
      await upgradeVault(vault, implementations['EthPrivErc20Vault'])
      await setBalance(await vault.admin(), parseEther('1000'))
      return vault
    },
    createEthBlocklistErc20Vault: async (
      admin: Wallet,
      vaultParams: EthErc20VaultInitParamsStruct,
      isOwnMevEscrow = false
    ): Promise<EthBlocklistErc20Vault> => {
      const tx = await ethBlocklistErc20VaultFactory
        .connect(admin)
        .createVault(encodeEthErc20VaultInitParams(vaultParams), isOwnMevEscrow, {
          value: SECURITY_DEPOSIT,
        })
      const vaultAddress = await extractVaultAddress(tx)
      return EthBlocklistErc20Vault__factory.connect(
        vaultAddress,
        await ethers.provider.getSigner()
      )
    },
    createEthGenesisVault: async (
      admin: Signer,
      vaultParams: EthVaultInitParamsStruct,
      skipFork: boolean = false
    ): Promise<[EthGenesisVault, LegacyRewardTokenMock, PoolEscrowMock]> => {
      let poolEscrow: PoolEscrowMock, rewardEthToken: LegacyRewardTokenMock
      if (!MAINNET_FORK.enabled || skipFork) {
        poolEscrow = await createPoolEscrow(dao.address, skipFork)
        const legacyRewardTokenMockFactory =
          await ethers.getContractFactory('LegacyRewardTokenMock')
        const legacyRewardTokenMock = await legacyRewardTokenMockFactory.deploy()
        rewardEthToken = LegacyRewardTokenMock__factory.connect(
          await legacyRewardTokenMock.getAddress(),
          dao
        )
      } else {
        poolEscrow = PoolEscrowMock__factory.connect(NETWORKS.mainnet.genesisVault.poolEscrow, dao)
        rewardEthToken = LegacyRewardTokenMock__factory.connect(
          NETWORKS.mainnet.genesisVault.rewardToken,
          dao
        )
      }

      const vaultImpl = await deployEthGenesisVaultImpl(
        keeper,
        vaultsRegistry,
        validatorsRegistry,
        osTokenVaultController,
        osTokenConfig,
        sharedMevEscrow,
        depositDataRegistry,
        poolEscrow,
        rewardEthToken
      )
      await vaultsRegistry.addVaultImpl(vaultImpl)

      let vault: EthGenesisVault
      if (!MAINNET_FORK.enabled || skipFork) {
        const proxyFactory = await ethers.getContractFactory('ERC1967Proxy')
        const proxy = await proxyFactory.deploy(vaultImpl, '0x')
        const proxyAddress = await proxy.getAddress()
        vault = EthGenesisVault__factory.connect(proxyAddress, await ethers.provider.getSigner())
        await rewardEthToken.connect(dao).setVault(proxyAddress)
        await poolEscrow.connect(dao).commitOwnershipTransfer(proxyAddress)
        const adminAddr = await admin.getAddress()
        await vault.initialize(
          ethers.AbiCoder.defaultAbiCoder().encode(
            ['address', 'tuple(uint256 capacity, uint16 feePercent, string metadataIpfsHash)'],
            [
              adminAddr,
              [vaultParams.capacity, vaultParams.feePercent, vaultParams.metadataIpfsHash],
            ]
          ),
          { value: SECURITY_DEPOSIT }
        )
        await vaultsRegistry.addVault(proxyAddress)
      } else {
        vault = EthGenesisVault__factory.connect(
          mainnetDeployment.EthGenesisVault,
          await ethers.provider.getSigner()
        )
        await upgradeVault(vault, vaultImpl)
        await updateVaultState(
          keeper,
          vault,
          MAINNET_FORK.harvestParams[mainnetDeployment.EthGenesisVault]
        )
      }
      await setBalance(await vault.admin(), parseEther('1000'))
      return [vault, rewardEthToken, poolEscrow]
    },
  }
}
