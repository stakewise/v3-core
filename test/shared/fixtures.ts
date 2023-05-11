import { ethers, upgrades } from 'hardhat'
import { Fixture } from 'ethereum-waffle'
import { BigNumberish, Contract, Wallet } from 'ethers'
import { arrayify, getContractAddress } from 'ethers/lib/utils'
import { signTypedData, SignTypedDataVersion } from '@metamask/eth-sig-util'
import EthereumWallet from 'ethereumjs-wallet'
import {
  EthVault,
  EthPrivateVault,
  IEthVaultFactory,
  EthVaultFactory,
  EthVaultMock,
  VaultsRegistry,
  Oracles,
  Keeper,
  SharedMevEscrow,
  OsToken,
  OsTokenConfig,
} from '../../typechain-types'
import { getValidatorsRegistryFactory } from './contracts'
import {
  REQUIRED_ORACLES,
  ORACLES,
  ORACLES_CONFIG,
  SECURITY_DEPOSIT,
  REWARDS_DELAY,
  OSTOKEN_FEE,
  OSTOKEN_NAME,
  OSTOKEN_SYMBOL,
  OSTOKEN_CAPACITY,
  OSTOKEN_LIQ_THRESHOLD,
  OSTOKEN_LIQ_BONUS,
  OSTOKEN_LTV,
  OSTOKEN_REDEEM_START_HF,
  OSTOKEN_REDEEM_MAX_HF,
} from './constants'

export const createValidatorsRegistry = async function (): Promise<Contract> {
  const validatorsRegistryFactory = await getValidatorsRegistryFactory()
  return validatorsRegistryFactory.deploy()
}

export const createVaultsRegistry = async function (owner: Wallet): Promise<VaultsRegistry> {
  const factory = await ethers.getContractFactory('VaultsRegistry')
  return (await factory.deploy(owner.address)) as VaultsRegistry
}

export const createSharedMevEscrow = async function (
  vaultsRegistry: VaultsRegistry
): Promise<SharedMevEscrow> {
  const factory = await ethers.getContractFactory('SharedMevEscrow')
  return (await factory.deploy(vaultsRegistry.address)) as SharedMevEscrow
}

export const createOracles = async function (
  owner: Wallet,
  initialOracles: string[],
  initialRequiredOracles: number,
  configIpfsHash: string
): Promise<Oracles> {
  const factory = await ethers.getContractFactory('Oracles')
  return (await factory.deploy(
    owner.address,
    initialOracles,
    initialRequiredOracles,
    configIpfsHash
  )) as Oracles
}

export const createOsToken = async function (
  keeperAddress: string,
  vaultsRegistry: VaultsRegistry,
  owner: Wallet,
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
    owner.address,
    treasury.address,
    feePercent,
    capacity,
    name,
    symbol
  )) as OsToken
}

export const createOsTokenConfig = async function (
  owner: Wallet,
  redeemStartHealthFactor: BigNumberish,
  redeemMaxHealthFactor: BigNumberish,
  osTokenLiqThreshold: BigNumberish,
  osTokenLiqBonus: BigNumberish,
  osTokenLtv: BigNumberish
): Promise<OsTokenConfig> {
  const factory = await ethers.getContractFactory('OsTokenConfig')
  return (await factory.deploy(
    owner.address,
    redeemStartHealthFactor,
    redeemMaxHealthFactor,
    osTokenLiqThreshold,
    osTokenLiqBonus,
    osTokenLtv
  )) as OsTokenConfig
}

export const createKeeper = async function (
  owner: Wallet,
  oracles: Oracles,
  vaultsRegistry: VaultsRegistry,
  osToken: OsToken,
  validatorsRegistry: Contract,
  sharedMevEscrow: SharedMevEscrow
): Promise<Keeper> {
  const factory = await ethers.getContractFactory('Keeper')
  const instance = await upgrades.deployProxy(factory, [owner.address, REWARDS_DELAY], {
    unsafeAllow: ['delegatecall'],
    constructorArgs: [
      sharedMevEscrow.address,
      oracles.address,
      vaultsRegistry.address,
      osToken.address,
      validatorsRegistry.address,
    ],
  })
  return (await instance.deployed()) as Keeper
}

export const createEthVaultFactory = async function (
  keeper: Keeper,
  vaultsRegistry: VaultsRegistry,
  sharedMevEscrow: SharedMevEscrow,
  validatorsRegistry: Contract,
  osToken: OsToken,
  osTokenConfig: OsTokenConfig
): Promise<EthVaultFactory> {
  const ethVault = await ethers.getContractFactory('EthVault')
  const ethVaultImpl = await upgrades.deployImplementation(ethVault, {
    unsafeAllow: ['delegatecall'],
    constructorArgs: [
      keeper.address,
      vaultsRegistry.address,
      validatorsRegistry.address,
      osToken.address,
      osTokenConfig.address,
      sharedMevEscrow.address,
    ],
  })

  const ethPrivateVault = await ethers.getContractFactory('EthPrivateVault')
  const ethPrivateVaultImpl = await upgrades.deployImplementation(ethPrivateVault, {
    unsafeAllow: ['delegatecall'],
    constructorArgs: [
      keeper.address,
      vaultsRegistry.address,
      validatorsRegistry.address,
      osToken.address,
      osTokenConfig.address,
      sharedMevEscrow.address,
    ],
  })

  const factory = await ethers.getContractFactory('EthVaultFactory')
  return (await factory.deploy(
    ethVaultImpl,
    ethPrivateVaultImpl,
    vaultsRegistry.address
  )) as EthVaultFactory
}

export const createEthVaultMockFactory = async function (
  keeper: Keeper,
  vaultsRegistry: VaultsRegistry,
  sharedMevEscrow: SharedMevEscrow,
  validatorsRegistry: Contract,
  osToken: OsToken,
  osTokenConfig: OsTokenConfig
): Promise<EthVaultFactory> {
  const ethVaultMock = await ethers.getContractFactory('EthVaultMock')
  const ethVaultMockImpl = await upgrades.deployImplementation(ethVaultMock, {
    unsafeAllow: ['delegatecall'],
    constructorArgs: [
      keeper.address,
      vaultsRegistry.address,
      validatorsRegistry.address,
      osToken.address,
      osTokenConfig.address,
      sharedMevEscrow.address,
    ],
  })

  const ethPrivateVault = await ethers.getContractFactory('EthPrivateVault')
  const ethPrivateVaultImpl = await upgrades.deployImplementation(ethPrivateVault, {
    unsafeAllow: ['delegatecall'],
    constructorArgs: [
      keeper.address,
      vaultsRegistry.address,
      validatorsRegistry.address,
      osToken.address,
      osTokenConfig.address,
      sharedMevEscrow.address,
    ],
  })

  const factory = await ethers.getContractFactory('EthVaultFactory')
  return (await factory.deploy(
    ethVaultMockImpl,
    ethPrivateVaultImpl,
    vaultsRegistry.address
  )) as EthVaultFactory
}

interface EthVaultFixture {
  vaultsRegistry: VaultsRegistry
  oracles: Oracles
  keeper: Keeper
  sharedMevEscrow: SharedMevEscrow
  validatorsRegistry: Contract
  ethVaultFactory: EthVaultFactory
  osToken: OsToken
  osTokenConfig: OsTokenConfig
  getSignatures: (typedData: any, count?: number) => Buffer

  createVault(
    admin: Wallet,
    vaultParams: IEthVaultFactory.VaultParamsStruct,
    isOwnMevEscrow?: boolean
  ): Promise<EthVault>

  createPrivateVault(
    admin: Wallet,
    vaultParams: IEthVaultFactory.VaultParamsStruct,
    isOwnMevEscrow?: boolean
  ): Promise<EthPrivateVault>

  createVaultMock(
    admin: Wallet,
    vaultParams: IEthVaultFactory.VaultParamsStruct,
    isOwnMevEscrow?: boolean
  ): Promise<EthVaultMock>
}

export const ethVaultFixture: Fixture<EthVaultFixture> = async function ([
  dao,
]): Promise<EthVaultFixture> {
  const vaultsRegistry = await createVaultsRegistry(dao)
  const validatorsRegistry = await createValidatorsRegistry()

  const sortedOracles = ORACLES.sort((oracle1, oracle2) => {
    const oracle1Addr = new EthereumWallet(oracle1).getAddressString()
    const oracle2Addr = new EthereumWallet(oracle2).getAddressString()
    return oracle1Addr > oracle2Addr ? 1 : -1
  })
  const oracles = await createOracles(
    dao,
    sortedOracles.map((s) => new EthereumWallet(s).getAddressString()),
    REQUIRED_ORACLES,
    ORACLES_CONFIG
  )
  const sharedMevEscrow = await createSharedMevEscrow(vaultsRegistry)

  // 2. calc keeper address
  const [_deployer] = await ethers.getSigners()
  const _keeperAddress = getContractAddress({
    from: _deployer.address,
    nonce: (await _deployer.getTransactionCount()) + 2,
  })

  // 3. deploy ostoken
  const osToken = await createOsToken(
    _keeperAddress,
    vaultsRegistry,
    dao,
    dao,
    OSTOKEN_FEE,
    OSTOKEN_CAPACITY,
    OSTOKEN_NAME,
    OSTOKEN_SYMBOL
  )

  // 4. deploy keeper
  const keeper = await createKeeper(
    dao,
    oracles,
    vaultsRegistry,
    osToken,
    validatorsRegistry,
    sharedMevEscrow
  )

  // 5. verify keeper address
  if (_keeperAddress != keeper.address) {
    throw new Error('Invalid calculated Keeper address')
  }

  const osTokenConfig = await createOsTokenConfig(
    dao,
    OSTOKEN_REDEEM_START_HF,
    OSTOKEN_REDEEM_MAX_HF,
    OSTOKEN_LIQ_THRESHOLD,
    OSTOKEN_LIQ_BONUS,
    OSTOKEN_LTV
  )

  const ethVaultFactory = await createEthVaultFactory(
    keeper,
    vaultsRegistry,
    sharedMevEscrow,
    validatorsRegistry,
    osToken,
    osTokenConfig
  )
  await vaultsRegistry.connect(dao).addFactory(ethVaultFactory.address)

  const ethVaultMockFactory = await createEthVaultMockFactory(
    keeper,
    vaultsRegistry,
    sharedMevEscrow,
    validatorsRegistry,
    osToken,
    osTokenConfig
  )
  await vaultsRegistry.connect(dao).addFactory(ethVaultMockFactory.address)

  const ethVault = await ethers.getContractFactory('EthVault')
  const ethPrivateVault = await ethers.getContractFactory('EthPrivateVault')
  const ethVaultMock = await ethers.getContractFactory('EthVaultMock')
  return {
    vaultsRegistry,
    sharedMevEscrow,
    oracles,
    keeper,
    validatorsRegistry,
    ethVaultFactory,
    osToken,
    osTokenConfig,
    createVault: async (
      admin: Wallet,
      vaultParams: IEthVaultFactory.VaultParamsStruct,
      isOwnMevEscrow = false
    ): Promise<EthVault> => {
      const tx = await ethVaultFactory
        .connect(admin)
        .createVault(vaultParams, false, isOwnMevEscrow, { value: SECURITY_DEPOSIT })
      const receipt = await tx.wait()
      const vaultAddress = receipt.events?.[receipt.events.length - 1].args?.vault as string
      return ethVault.attach(vaultAddress) as EthVault
    },
    createPrivateVault: async (
      admin: Wallet,
      vaultParams: IEthVaultFactory.VaultParamsStruct,
      isOwnMevEscrow = false
    ): Promise<EthPrivateVault> => {
      const tx = await ethVaultFactory
        .connect(admin)
        .createVault(vaultParams, true, isOwnMevEscrow, { value: SECURITY_DEPOSIT })
      const receipt = await tx.wait()
      const vaultAddress = receipt.events?.[receipt.events.length - 1].args?.vault as string
      return ethPrivateVault.attach(vaultAddress) as EthPrivateVault
    },
    createVaultMock: async (
      admin: Wallet,
      vaultParams: IEthVaultFactory.VaultParamsStruct,
      isOwnMevEscrow = false
    ): Promise<EthVaultMock> => {
      const tx = await ethVaultMockFactory
        .connect(admin)
        .createVault(vaultParams, false, isOwnMevEscrow, { value: SECURITY_DEPOSIT })
      const receipt = await tx.wait()
      const vaultAddress = receipt.events?.[receipt.events.length - 1].args?.vault as string
      return ethVaultMock.attach(vaultAddress) as EthVaultMock
    },
    getSignatures: (typedData: any, count: number = REQUIRED_ORACLES): Buffer => {
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
    },
  }
}
