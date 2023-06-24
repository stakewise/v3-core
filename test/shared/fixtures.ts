import { ethers, upgrades } from 'hardhat'
import { Fixture } from 'ethereum-waffle'
import { BigNumberish, Contract, Wallet } from 'ethers'
import { arrayify, getContractAddress } from 'ethers/lib/utils'
import { signTypedData, SignTypedDataVersion } from '@metamask/eth-sig-util'
import EthereumWallet from 'ethereumjs-wallet'
import {
  EthErc20Vault,
  EthPrivErc20Vault,
  EthPrivVault,
  EthVault,
  EthVaultFactory,
  EthVaultMock,
  Keeper,
  OsToken,
  OsTokenConfig,
  PriceOracle,
  SharedMevEscrow,
  VaultsRegistry,
  PoolEscrowMock,
} from '../../typechain-types'
import { getValidatorsRegistryFactory } from './contracts'
import {
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

export const createValidatorsRegistry = async function (): Promise<Contract> {
  const validatorsRegistryFactory = await getValidatorsRegistryFactory()
  return validatorsRegistryFactory.deploy()
}

export const createPoolEscrow = async function (
  stakedEthTokenAddress: string
): Promise<PoolEscrowMock> {
  const factory = await ethers.getContractFactory('PoolEscrowMock')
  return (await factory.deploy(stakedEthTokenAddress)) as PoolEscrowMock
}

export const createVaultsRegistry = async function (): Promise<VaultsRegistry> {
  const factory = await ethers.getContractFactory('VaultsRegistry')
  return (await factory.deploy()) as VaultsRegistry
}

export const createSharedMevEscrow = async function (
  vaultsRegistry: VaultsRegistry
): Promise<SharedMevEscrow> {
  const factory = await ethers.getContractFactory('SharedMevEscrow')
  return (await factory.deploy(vaultsRegistry.address)) as SharedMevEscrow
}

export const createPriceOracle = async function (osToken: OsToken): Promise<PriceOracle> {
  const factory = await ethers.getContractFactory('PriceOracle')
  return (await factory.deploy(osToken.address)) as PriceOracle
}

export const createOsToken = async function (
  keeperAddress: string,
  vaultsRegistry: VaultsRegistry,
  treasury: Wallet,
  feePercent: BigNumberish,
  capacity: BigNumberish,
  name: string,
  symbol: string
): Promise<OsToken> {
  const factory = await ethers.getContractFactory('OsToken')
  return (await factory.deploy(
    keeperAddress,
    vaultsRegistry.address,
    treasury.address,
    feePercent,
    capacity,
    name,
    symbol
  )) as OsToken
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
  return (await factory.deploy(owner.address, {
    redeemFromLtvPercent,
    redeemToLtvPercent,
    liqThresholdPercent,
    liqBonusPercent,
    ltvPercent,
  })) as OsTokenConfig
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
  const keeper = (await factory.deploy(
    sharedMevEscrow.address,
    vaultsRegistry.address,
    osToken.address,
    rewardsDelay,
    maxAvgRewardPerSecond,
    validatorsRegistry.address
  )) as Keeper
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
  return (await factory.deploy(implementation, vaultsRegistry.address)) as EthVaultFactory
}

export const encodeEthVaultInitParams = function (vaultParams: EthVaultInitParamsStruct): string {
  return ethers.utils.defaultAbiCoder.encode(
    ['tuple(uint256 capacity, uint16 feePercent, string metadataIpfsHash)'],
    [[vaultParams.capacity, vaultParams.feePercent, vaultParams.metadataIpfsHash]]
  )
}

export const encodeEthErc20VaultInitParams = function (
  vaultParams: EthErc20VaultInitParamsStruct
): string {
  return ethers.utils.defaultAbiCoder.encode(
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
        arrayify(
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

export const ethVaultFixture: Fixture<EthVaultFixture> = async function ([
  dao,
]): Promise<EthVaultFixture> {
  const vaultsRegistry = await createVaultsRegistry()
  const validatorsRegistry = await createValidatorsRegistry()

  const sharedMevEscrow = await createSharedMevEscrow(vaultsRegistry)

  // 2. calc keeper address
  const [_deployer] = await ethers.getSigners()
  const _keeperAddress = getContractAddress({
    from: _deployer.address,
    nonce: (await _deployer.getTransactionCount()) + 1,
  })

  // 3. deploy ostoken
  const osToken = await createOsToken(
    _keeperAddress,
    vaultsRegistry,
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
  if (_keeperAddress != keeper.address) {
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
        keeper.address,
        vaultsRegistry.address,
        validatorsRegistry.address,
        osToken.address,
        osTokenConfig.address,
        sharedMevEscrow.address,
      ],
    })) as string
    const vaultFactory = await createEthVaultFactory(vaultImpl, vaultsRegistry)
    await vaultsRegistry.addFactory(vaultFactory.address)
    await osToken.setVaultImplementation(vaultImpl, true)
    factories.push(vaultFactory)
  }

  // change ownership
  await vaultsRegistry.transferOwnership(dao.address)
  await vaultsRegistry.connect(dao).acceptOwnership()
  await keeper.transferOwnership(dao.address)
  await keeper.connect(dao).acceptOwnership()
  await osToken.transferOwnership(dao.address)
  await osToken.connect(dao).acceptOwnership()

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
      const receipt = await tx.wait()
      const vaultAddress = extractVaultAddress(receipt)
      const ethVault = await ethers.getContractFactory('EthVault')
      return ethVault.attach(vaultAddress) as EthVault
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
      const receipt = await tx.wait()
      const vaultAddress = extractVaultAddress(receipt)
      const ethVaultMock = await ethers.getContractFactory('EthVaultMock')
      return ethVaultMock.attach(vaultAddress) as EthVaultMock
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
      const receipt = await tx.wait()
      const vaultAddress = extractVaultAddress(receipt)
      const ethPrivVault = await ethers.getContractFactory('EthPrivVault')
      return ethPrivVault.attach(vaultAddress) as EthPrivVault
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
      const receipt = await tx.wait()
      const vaultAddress = extractVaultAddress(receipt)
      const ethErc20Vault = await ethers.getContractFactory('EthErc20Vault')
      return ethErc20Vault.attach(vaultAddress) as EthErc20Vault
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
      const receipt = await tx.wait()
      const vaultAddress = extractVaultAddress(receipt)
      const ethPrivErc20Vault = await ethers.getContractFactory('EthPrivErc20Vault')
      return ethPrivErc20Vault.attach(vaultAddress) as EthPrivErc20Vault
    },
  }
}
