import { ethers, upgrades } from 'hardhat'
import { BigNumberish, Contract, Wallet } from 'ethers'
import { signTypedData, SignTypedDataVersion } from '@metamask/eth-sig-util'
import EthereumWallet from 'ethereumjs-wallet'
import {
  CumulativeMerkleDrop,
  CumulativeMerkleDrop__factory,
  EthErc20Vault,
  EthErc20Vault__factory,
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
  Keeper,
  Keeper__factory,
  OsToken,
  OsToken__factory,
  OsTokenChecker,
  OsTokenChecker__factory,
  OsTokenConfig,
  OsTokenConfig__factory,
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
} from '../../typechain-types'
import { getValidatorsRegistryFactory } from './contracts'
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
} from './constants'
import { EthErc20VaultInitParamsStruct, EthVaultInitParamsStruct } from './types'
import { extractVaultAddress } from './utils'
import { DepositorMock } from '../../typechain-types/contracts/mocks/DepositorMock'
import { DepositorMock__factory } from '../../typechain-types/factories/contracts/mocks/DepositorMock__factory'
import { UnknownVaultMock } from '../../typechain-types/contracts/mocks/UnknownVaultMock'
import { UnknownVaultMock__factory } from '../../typechain-types/factories/contracts/mocks/UnknownVaultMock__factory'
import { MulticallMock__factory } from '../../typechain-types/factories/contracts/mocks/MulticallMock__factory'
import { MulticallMock } from '../../typechain-types/contracts/mocks/MulticallMock'

export const createDepositorMock = async function (vault: EthVault): Promise<DepositorMock> {
  const depositorMockFactory = await ethers.getContractFactory('DepositorMock')
  const contract = await depositorMockFactory.deploy(await vault.getAddress())
  return DepositorMock__factory.connect(
    await contract.getAddress(),
    await ethers.provider.getSigner()
  )
}

export const createUnknownVaultMock = async function (
  osToken: OsToken,
  implementation: string
): Promise<UnknownVaultMock> {
  const factory = await ethers.getContractFactory('UnknownVaultMock')
  const contract = await factory.deploy(await osToken.getAddress(), implementation)
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
export const createValidatorsRegistry = async function (): Promise<Contract> {
  const validatorsRegistryFactory = await getValidatorsRegistryFactory()
  const contract = await validatorsRegistryFactory.deploy()
  return new Contract(
    await contract.getAddress(),
    validatorsRegistryFactory.interface,
    await ethers.provider.getSigner()
  )
}

export const createPoolEscrow = async function (
  stakedEthTokenAddress: string
): Promise<PoolEscrowMock> {
  const factory = await ethers.getContractFactory('PoolEscrowMock')
  const contract = await factory.deploy(stakedEthTokenAddress)
  return PoolEscrowMock__factory.connect(
    await contract.getAddress(),
    await ethers.provider.getSigner()
  )
}

export const createVaultsRegistry = async function (): Promise<VaultsRegistry> {
  const factory = await ethers.getContractFactory('VaultsRegistry')
  const contract = await factory.deploy()
  return VaultsRegistry__factory.connect(
    await contract.getAddress(),
    await ethers.provider.getSigner()
  )
}

export const createSharedMevEscrow = async function (
  vaultsRegistry: VaultsRegistry
): Promise<SharedMevEscrow> {
  const factory = await ethers.getContractFactory('SharedMevEscrow')
  const contract = await factory.deploy(await vaultsRegistry.getAddress())
  return SharedMevEscrow__factory.connect(
    await contract.getAddress(),
    await ethers.provider.getSigner()
  )
}

export const createPriceFeed = async function (
  osToken: OsToken,
  description: string
): Promise<PriceFeed> {
  const factory = await ethers.getContractFactory('PriceFeed')
  const contract = await factory.deploy(await osToken.getAddress(), description)
  return PriceFeed__factory.connect(await contract.getAddress(), await ethers.provider.getSigner())
}

export const createRewardSplitterFactory = async function (): Promise<RewardSplitterFactory> {
  let factory = await ethers.getContractFactory('RewardSplitter')
  const rewardSplitterImpl = await factory.deploy()

  factory = await ethers.getContractFactory('RewardSplitterFactory')
  const contract = await factory.deploy(await rewardSplitterImpl.getAddress())
  return RewardSplitterFactory__factory.connect(
    await contract.getAddress(),
    await ethers.provider.getSigner()
  )
}

export const createOsToken = async function (
  keeperAddress: string,
  checker: OsTokenChecker,
  treasury: Wallet,
  governor: Wallet,
  feePercent: BigNumberish,
  capacity: BigNumberish,
  name: string,
  symbol: string
): Promise<OsToken> {
  const factory = await ethers.getContractFactory('OsToken')
  const contract = await factory.deploy(
    keeperAddress,
    await checker.getAddress(),
    treasury.address,
    governor.address,
    feePercent,
    capacity,
    name,
    symbol
  )
  return OsToken__factory.connect(await contract.getAddress(), await ethers.provider.getSigner())
}

export const createOsTokenChecker = async function (
  vaultsRegistry: VaultsRegistry
): Promise<OsTokenChecker> {
  const factory = await ethers.getContractFactory('OsTokenChecker')
  const contract = await factory.deploy(await vaultsRegistry.getAddress())
  return OsTokenChecker__factory.connect(
    await contract.getAddress(),
    await ethers.provider.getSigner()
  )
}

export const createOsTokenConfig = async function (
  owner: Wallet,
  redeemFromLtvPercent: BigNumberish,
  redeemToLtvPercent: BigNumberish,
  liqThresholdPercent: BigNumberish,
  liqBonusPercent: BigNumberish,
  ltvPercent: BigNumberish
): Promise<OsTokenConfig> {
  const factory = await ethers.getContractFactory('OsTokenConfig')
  const contract = await factory.deploy(owner.address, {
    redeemFromLtvPercent,
    redeemToLtvPercent,
    liqThresholdPercent,
    liqBonusPercent,
    ltvPercent,
  })
  return OsTokenConfig__factory.connect(
    await contract.getAddress(),
    await ethers.provider.getSigner()
  )
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
  osToken: OsToken,
  rewardsDelay: BigNumberish,
  maxAvgRewardPerSecond: BigNumberish,
  rewardsMinOracles: BigNumberish,
  validatorsRegistry: Contract,
  validatorsMinOracles: BigNumberish
): Promise<Keeper> {
  const factory = await ethers.getContractFactory('Keeper')
  const contract = await factory.deploy(
    await sharedMevEscrow.getAddress(),
    await vaultsRegistry.getAddress(),
    await osToken.getAddress(),
    rewardsDelay,
    maxAvgRewardPerSecond,
    await validatorsRegistry.getAddress()
  )
  const keeper = Keeper__factory.connect(
    await contract.getAddress(),
    await ethers.provider.getSigner()
  )
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
  validatorsRegistry: Contract
  ethVaultFactory: EthVaultFactory
  ethVaultMockFactory: EthVaultFactory
  ethPrivVaultFactory: EthVaultFactory
  ethErc20VaultFactory: EthVaultFactory
  ethPrivErc20VaultFactory: EthVaultFactory
  osToken: OsToken
  osTokenConfig: OsTokenConfig
  osTokenChecker: OsTokenChecker

  createEthVault(
    admin: Wallet,
    vaultParams: EthVaultInitParamsStruct,
    isOwnMevEscrow?: boolean
  ): Promise<EthVault>

  createEthVaultMock(
    admin: Wallet,
    vaultParams: EthVaultInitParamsStruct,
    isOwnMevEscrow?: boolean
  ): Promise<EthVaultMock>

  createEthPrivVault(
    admin: Wallet,
    vaultParams: EthVaultInitParamsStruct,
    isOwnMevEscrow?: boolean
  ): Promise<EthPrivVault>

  createEthErc20Vault(
    admin: Wallet,
    vaultParams: EthErc20VaultInitParamsStruct,
    isOwnMevEscrow?: boolean
  ): Promise<EthErc20Vault>

  createEthPrivErc20Vault(
    admin: Wallet,
    vaultParams: EthErc20VaultInitParamsStruct,
    isOwnMevEscrow?: boolean
  ): Promise<EthPrivErc20Vault>
}

export const ethVaultFixture = async function (): Promise<EthVaultFixture> {
  const dao = await (ethers as any).provider.getSigner()
  const vaultsRegistry = await createVaultsRegistry()
  const validatorsRegistry = await createValidatorsRegistry()

  const sharedMevEscrow = await createSharedMevEscrow(vaultsRegistry)

  // 1. deploy osTokenChecker
  const osTokenChecker = await createOsTokenChecker(vaultsRegistry)

  // 2. calc keeper address
  const _keeperAddress = ethers.getCreateAddress({
    from: dao.address,
    nonce: (await ethers.provider.getTransactionCount(dao.address)) + 1,
  })

  // 3. deploy ostoken
  const osToken = await createOsToken(
    _keeperAddress,
    osTokenChecker,
    dao,
    dao,
    OSTOKEN_FEE,
    OSTOKEN_CAPACITY,
    OSTOKEN_NAME,
    OSTOKEN_SYMBOL
  )

  // 4. deploy keeper
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
    osToken,
    REWARDS_DELAY,
    MAX_AVG_REWARD_PER_SECOND,
    REWARDS_MIN_ORACLES,
    validatorsRegistry,
    VALIDATORS_MIN_ORACLES
  )

  // 5. verify keeper address
  if (_keeperAddress != (await keeper.getAddress())) {
    throw new Error('Invalid calculated Keeper address')
  }

  const osTokenConfig = await createOsTokenConfig(
    dao,
    OSTOKEN_REDEEM_FROM_LTV,
    OSTOKEN_REDEEM_TO_LTV,
    OSTOKEN_LIQ_THRESHOLD,
    OSTOKEN_LIQ_BONUS,
    OSTOKEN_LTV
  )

  // 6. deploy implementations and factories
  const factories: EthVaultFactory[] = []
  for (const vaultType of [
    'EthVault',
    'EthVaultMock',
    'EthPrivVault',
    'EthErc20Vault',
    'EthPrivErc20Vault',
  ]) {
    const vault = await ethers.getContractFactory(vaultType)
    const vaultImpl = (await upgrades.deployImplementation(vault, {
      unsafeAllow: ['delegatecall'],
      constructorArgs: [
        await keeper.getAddress(),
        await vaultsRegistry.getAddress(),
        await validatorsRegistry.getAddress(),
        await osToken.getAddress(),
        await osTokenConfig.getAddress(),
        await sharedMevEscrow.getAddress(),
        EXITING_ASSETS_MIN_DELAY,
      ],
    })) as string
    const vaultFactory = await createEthVaultFactory(vaultImpl, vaultsRegistry)
    await vaultsRegistry.addFactory(await vaultFactory.getAddress())
    await vaultsRegistry.addVaultImpl(vaultImpl)
    factories.push(vaultFactory)
  }

  // change ownership
  await vaultsRegistry.initialize(dao.address)
  await keeper.initialize(dao.address)

  return {
    vaultsRegistry,
    sharedMevEscrow,
    keeper,
    validatorsRegistry,
    ethVaultFactory: factories[0],
    ethVaultMockFactory: factories[1],
    ethPrivVaultFactory: factories[2],
    ethErc20VaultFactory: factories[3],
    ethPrivErc20VaultFactory: factories[4],
    osToken,
    osTokenConfig,
    osTokenChecker,
    createEthVault: async (
      admin: Wallet,
      vaultParams: EthVaultInitParamsStruct,
      isOwnMevEscrow = false
    ): Promise<EthVault> => {
      const tx = await factories[0]
        .connect(admin)
        .createVault(encodeEthVaultInitParams(vaultParams), isOwnMevEscrow, {
          value: SECURITY_DEPOSIT,
        })
      const vaultAddress = await extractVaultAddress(tx)
      return EthVault__factory.connect(vaultAddress, await ethers.provider.getSigner())
    },
    createEthVaultMock: async (
      admin: Wallet,
      vaultParams: EthVaultInitParamsStruct,
      isOwnMevEscrow = false
    ): Promise<EthVaultMock> => {
      const tx = await factories[1]
        .connect(admin)
        .createVault(encodeEthVaultInitParams(vaultParams), isOwnMevEscrow, {
          value: SECURITY_DEPOSIT,
        })
      const vaultAddress = await extractVaultAddress(tx)
      return EthVaultMock__factory.connect(vaultAddress, await ethers.provider.getSigner())
    },
    createEthPrivVault: async (
      admin: Wallet,
      vaultParams: EthVaultInitParamsStruct,
      isOwnMevEscrow = false
    ): Promise<EthPrivVault> => {
      const tx = await factories[2]
        .connect(admin)
        .createVault(encodeEthVaultInitParams(vaultParams), isOwnMevEscrow, {
          value: SECURITY_DEPOSIT,
        })
      const vaultAddress = await extractVaultAddress(tx)
      return EthPrivVault__factory.connect(vaultAddress, await ethers.provider.getSigner())
    },
    createEthErc20Vault: async (
      admin: Wallet,
      vaultParams: EthErc20VaultInitParamsStruct,
      isOwnMevEscrow = false
    ): Promise<EthErc20Vault> => {
      const tx = await factories[3]
        .connect(admin)
        .createVault(encodeEthErc20VaultInitParams(vaultParams), isOwnMevEscrow, {
          value: SECURITY_DEPOSIT,
        })
      const vaultAddress = await extractVaultAddress(tx)
      return EthErc20Vault__factory.connect(vaultAddress, await ethers.provider.getSigner())
    },
    createEthPrivErc20Vault: async (
      admin: Wallet,
      vaultParams: EthErc20VaultInitParamsStruct,
      isOwnMevEscrow = false
    ): Promise<EthPrivErc20Vault> => {
      const tx = await factories[4]
        .connect(admin)
        .createVault(encodeEthErc20VaultInitParams(vaultParams), isOwnMevEscrow, {
          value: SECURITY_DEPOSIT,
        })
      const vaultAddress = await extractVaultAddress(tx)
      return EthPrivErc20Vault__factory.connect(vaultAddress, await ethers.provider.getSigner())
    },
  }
}
