import hre, { ethers } from 'hardhat'
import { Contract, Signer, Wallet } from 'ethers'
import { simulateDeployImpl } from '@openzeppelin/hardhat-upgrades/dist/utils'
import EthereumWallet from 'ethereumjs-wallet'
import {
  DepositDataRegistry,
  EthRestakeBlocklistErc20Vault,
  EthRestakeBlocklistErc20Vault__factory,
  EthRestakeBlocklistVault,
  EthRestakeBlocklistVault__factory,
  EthRestakeErc20Vault,
  EthRestakeErc20Vault__factory,
  EthRestakePrivErc20Vault,
  EthRestakePrivErc20Vault__factory,
  EthRestakePrivVault,
  EthRestakePrivVault__factory,
  EthRestakeVault,
  EthRestakeVault__factory,
  Keeper,
  SharedMevEscrow,
  VaultsRegistry,
  VaultsRegistry__factory,
  SharedMevEscrow__factory,
  Keeper__factory,
  EthRestakeVaultFactory,
  EthRestakeVaultFactory__factory,
} from '../../typechain-types'
import {
  EXITING_ASSETS_MIN_DELAY,
  ORACLES,
  ORACLES_CONFIG,
  REWARDS_MIN_ORACLES,
  SECURITY_DEPOSIT,
  VALIDATORS_MIN_ORACLES,
} from './constants'
import { EthRestakeErc20VaultInitParamsStruct, EthRestakeVaultInitParamsStruct } from './types'
import { extractVaultAddress } from './utils'
import { createDepositDataRegistry, transferOwnership } from './fixtures'
import { MAINNET_FORK, NETWORKS } from '../../helpers/constants'
import { getEthValidatorsRegistryFactory } from './contracts'
import mainnetDeployment from '../../deployments/mainnet.json'

export const createEthRestakeVaultFactory = async function (
  dao: Signer,
  implementation: string,
  vaultsRegistry: VaultsRegistry
): Promise<EthRestakeVaultFactory> {
  const factory = await ethers.getContractFactory('EthRestakeVaultFactory')
  const contract = await factory.deploy(
    await dao.getAddress(),
    implementation,
    await vaultsRegistry.getAddress()
  )
  return EthRestakeVaultFactory__factory.connect(
    await contract.getAddress(),
    await ethers.provider.getSigner()
  )
}
export const deployEigenPodOwnerImplementation = async function (
  eigenPodManagerAddr: string,
  eigenDelegationManagerAddr: string,
  eigenDelayedWithdrawalRouterAddr: string
): Promise<string> {
  const factory = await ethers.getContractFactory('EigenPodOwner')
  const constructorArgs = [
    eigenPodManagerAddr,
    eigenDelegationManagerAddr,
    eigenDelayedWithdrawalRouterAddr,
  ]
  const contract = await factory.deploy(...constructorArgs)
  const eigenPodOwnerImpl = await contract.getAddress()
  await simulateDeployImpl(hre, factory, { constructorArgs }, eigenPodOwnerImpl)
  return eigenPodOwnerImpl
}

export const deployEthRestakeVaultImplementation = async function (
  vaultType: string,
  keeper: Keeper,
  vaultsRegistry: VaultsRegistry,
  validatorsRegistry: string,
  sharedMevEscrow: SharedMevEscrow,
  depositDataRegistry: DepositDataRegistry,
  eigenPodOwnerImpl: string,
  exitingAssetsMinDelay: number
): Promise<string> {
  const factory = await ethers.getContractFactory(vaultType)
  const constructorArgs = [
    await keeper.getAddress(),
    await vaultsRegistry.getAddress(),
    validatorsRegistry,
    await sharedMevEscrow.getAddress(),
    await depositDataRegistry.getAddress(),
    eigenPodOwnerImpl,
    exitingAssetsMinDelay,
  ]
  const contract = await factory.deploy(...constructorArgs)
  const vaultImpl = await contract.getAddress()
  await simulateDeployImpl(hre, factory, { constructorArgs }, vaultImpl)
  return vaultImpl
}

export const encodeEthRestakeVaultInitParams = function (
  vaultParams: EthRestakeVaultInitParamsStruct
): string {
  return ethers.AbiCoder.defaultAbiCoder().encode(
    ['tuple(uint256 capacity, uint16 feePercent, string metadataIpfsHash)'],
    [[vaultParams.capacity, vaultParams.feePercent, vaultParams.metadataIpfsHash]]
  )
}

export const encodeEthRestakeErc20VaultInitParams = function (
  vaultParams: EthRestakeErc20VaultInitParamsStruct
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

interface EthRestakeVaultFixture {
  vaultsRegistry: VaultsRegistry
  keeper: Keeper
  sharedMevEscrow: SharedMevEscrow
  depositDataRegistry: DepositDataRegistry
  validatorsRegistry: Contract
  ethRestakeVaultFactory: EthRestakeVaultFactory
  ethRestakePrivVaultFactory: EthRestakeVaultFactory
  ethRestakeErc20VaultFactory: EthRestakeVaultFactory
  ethRestakePrivErc20VaultFactory: EthRestakeVaultFactory
  ethRestakeBlocklistVaultFactory: EthRestakeVaultFactory
  ethRestakeBlocklistErc20VaultFactory: EthRestakeVaultFactory

  createEthRestakeVault(
    admin: Signer,
    vaultParams: EthRestakeVaultInitParamsStruct,
    isOwnMevEscrow?: boolean
  ): Promise<EthRestakeVault>

  createEthRestakePrivVault(
    admin: Signer,
    vaultParams: EthRestakeVaultInitParamsStruct,
    isOwnMevEscrow?: boolean
  ): Promise<EthRestakePrivVault>

  createEthRestakeBlocklistVault(
    admin: Signer,
    vaultParams: EthRestakeVaultInitParamsStruct,
    isOwnMevEscrow?: boolean
  ): Promise<EthRestakeBlocklistVault>

  createEthRestakeErc20Vault(
    admin: Signer,
    vaultParams: EthRestakeErc20VaultInitParamsStruct,
    isOwnMevEscrow?: boolean
  ): Promise<EthRestakeErc20Vault>

  createEthRestakePrivErc20Vault(
    admin: Signer,
    vaultParams: EthRestakeErc20VaultInitParamsStruct,
    isOwnMevEscrow?: boolean
  ): Promise<EthRestakePrivErc20Vault>

  createEthRestakeBlocklistErc20Vault(
    admin: Signer,
    vaultParams: EthRestakeErc20VaultInitParamsStruct,
    isOwnMevEscrow?: boolean
  ): Promise<EthRestakeBlocklistErc20Vault>
}

export const ethRestakeVaultFixture = async function (): Promise<EthRestakeVaultFixture> {
  const dao = await (ethers as any).provider.getSigner()

  const validatorsRegistryFactory = await getEthValidatorsRegistryFactory()
  const validatorsRegistry = new Contract(
    NETWORKS.mainnet.validatorsRegistry,
    validatorsRegistryFactory.interface,
    dao
  )
  const vaultsRegistry = VaultsRegistry__factory.connect(mainnetDeployment.VaultsRegistry, dao)
  const depositDataRegistry = await createDepositDataRegistry(vaultsRegistry)
  const sharedMevEscrow = SharedMevEscrow__factory.connect(mainnetDeployment.SharedMevEscrow, dao)
  const keeper = Keeper__factory.connect(mainnetDeployment.Keeper, dao)

  // change ownership
  await transferOwnership(vaultsRegistry, dao)
  await transferOwnership(keeper, dao)

  // drop mainnet oracles
  for (const oracleAddr of MAINNET_FORK.oracles) {
    if (await keeper.isOracle(oracleAddr)) {
      await keeper.removeOracle(oracleAddr)
    }
  }

  // add test oracles
  const sortedOracles = ORACLES.sort((oracle1, oracle2) => {
    const oracle1Addr = new EthereumWallet(oracle1).getAddressString()
    const oracle2Addr = new EthereumWallet(oracle2).getAddressString()
    return oracle1Addr > oracle2Addr ? 1 : -1
  })
  const sortedOraclesAddresses = sortedOracles.map((s) => new EthereumWallet(s).getAddressString())
  for (let i = 0; i < sortedOraclesAddresses.length; i++) {
    if (!(await keeper.isOracle(sortedOraclesAddresses[i]))) {
      await keeper.addOracle(sortedOraclesAddresses[i])
    }
  }

  await keeper.updateConfig(ORACLES_CONFIG)
  await keeper.setRewardsMinOracles(REWARDS_MIN_ORACLES)
  await keeper.setValidatorsMinOracles(VALIDATORS_MIN_ORACLES)

  const eigenPodOwnerImplementation = await deployEigenPodOwnerImplementation(
    MAINNET_FORK.eigenPodManager,
    MAINNET_FORK.eigenDelegationManager,
    MAINNET_FORK.eigenDelayedWithdrawalRouter
  )

  // deploy implementations and factories
  const factories = {}
  const implementations = {}

  for (const vaultType of [
    'EthRestakeVault',
    'EthRestakePrivVault',
    'EthRestakeErc20Vault',
    'EthRestakePrivErc20Vault',
    'EthRestakeBlocklistVault',
    'EthRestakeBlocklistErc20Vault',
  ]) {
    const vaultImpl = await deployEthRestakeVaultImplementation(
      vaultType,
      keeper,
      vaultsRegistry,
      await validatorsRegistry.getAddress(),
      sharedMevEscrow,
      depositDataRegistry,
      eigenPodOwnerImplementation,
      EXITING_ASSETS_MIN_DELAY
    )
    await vaultsRegistry.addVaultImpl(vaultImpl)
    implementations[vaultType] = vaultImpl

    const vaultFactory = await createEthRestakeVaultFactory(dao, vaultImpl, vaultsRegistry)
    await vaultsRegistry.addFactory(await vaultFactory.getAddress())
    factories[vaultType] = vaultFactory
  }

  const ethRestakeVaultFactory = factories['EthRestakeVault']
  const ethRestakePrivVaultFactory = factories['EthRestakePrivVault']
  const ethRestakeErc20VaultFactory = factories['EthRestakeErc20Vault']
  const ethRestakePrivErc20VaultFactory = factories['EthRestakePrivErc20Vault']
  const ethRestakeBlocklistVaultFactory = factories['EthRestakeBlocklistVault']
  const ethRestakeBlocklistErc20VaultFactory = factories['EthRestakeBlocklistErc20Vault']

  return {
    vaultsRegistry,
    sharedMevEscrow,
    depositDataRegistry,
    keeper,
    validatorsRegistry,
    ethRestakeVaultFactory,
    ethRestakePrivVaultFactory,
    ethRestakeErc20VaultFactory,
    ethRestakePrivErc20VaultFactory,
    ethRestakeBlocklistVaultFactory,
    ethRestakeBlocklistErc20VaultFactory,
    createEthRestakeVault: async (
      admin: Signer,
      vaultParams: EthRestakeVaultInitParamsStruct,
      isOwnMevEscrow = false
    ): Promise<EthRestakeVault> => {
      const tx = await ethRestakeVaultFactory.createVault(
        await admin.getAddress(),
        encodeEthRestakeVaultInitParams(vaultParams),
        isOwnMevEscrow,
        {
          value: SECURITY_DEPOSIT,
        }
      )
      const vaultAddress = await extractVaultAddress(tx)
      return EthRestakeVault__factory.connect(vaultAddress, await ethers.provider.getSigner())
    },
    createEthRestakePrivVault: async (
      admin: Signer,
      vaultParams: EthRestakeVaultInitParamsStruct,
      isOwnMevEscrow = false
    ): Promise<EthRestakePrivVault> => {
      const tx = await ethRestakePrivVaultFactory.createVault(
        await admin.getAddress(),
        encodeEthRestakeVaultInitParams(vaultParams),
        isOwnMevEscrow,
        {
          value: SECURITY_DEPOSIT,
        }
      )
      const vaultAddress = await extractVaultAddress(tx)
      return EthRestakePrivVault__factory.connect(vaultAddress, await ethers.provider.getSigner())
    },
    createEthRestakeBlocklistVault: async (
      admin: Signer,
      vaultParams: EthRestakeVaultInitParamsStruct,
      isOwnMevEscrow = false
    ): Promise<EthRestakeBlocklistVault> => {
      const tx = await ethRestakeBlocklistVaultFactory.createVault(
        await admin.getAddress(),
        encodeEthRestakeVaultInitParams(vaultParams),
        isOwnMevEscrow,
        {
          value: SECURITY_DEPOSIT,
        }
      )
      const vaultAddress = await extractVaultAddress(tx)
      return EthRestakeBlocklistVault__factory.connect(
        vaultAddress,
        await ethers.provider.getSigner()
      )
    },
    createEthRestakeErc20Vault: async (
      admin: Signer,
      vaultParams: EthRestakeErc20VaultInitParamsStruct,
      isOwnMevEscrow = false
    ): Promise<EthRestakeErc20Vault> => {
      const tx = await ethRestakeErc20VaultFactory.createVault(
        await admin.getAddress(),
        encodeEthRestakeErc20VaultInitParams(vaultParams),
        isOwnMevEscrow,
        {
          value: SECURITY_DEPOSIT,
        }
      )
      const vaultAddress = await extractVaultAddress(tx)
      return EthRestakeErc20Vault__factory.connect(vaultAddress, await ethers.provider.getSigner())
    },
    createEthRestakePrivErc20Vault: async (
      admin: Signer,
      vaultParams: EthRestakeErc20VaultInitParamsStruct,
      isOwnMevEscrow = false
    ): Promise<EthRestakePrivErc20Vault> => {
      const tx = await ethRestakePrivErc20VaultFactory.createVault(
        await admin.getAddress(),
        encodeEthRestakeErc20VaultInitParams(vaultParams),
        isOwnMevEscrow,
        {
          value: SECURITY_DEPOSIT,
        }
      )
      const vaultAddress = await extractVaultAddress(tx)
      return EthRestakePrivErc20Vault__factory.connect(
        vaultAddress,
        await ethers.provider.getSigner()
      )
    },
    createEthRestakeBlocklistErc20Vault: async (
      admin: Wallet,
      vaultParams: EthRestakeErc20VaultInitParamsStruct,
      isOwnMevEscrow = false
    ): Promise<EthRestakeBlocklistErc20Vault> => {
      const tx = await ethRestakeBlocklistErc20VaultFactory.createVault(
        await admin.getAddress(),
        encodeEthRestakeErc20VaultInitParams(vaultParams),
        isOwnMevEscrow,
        {
          value: SECURITY_DEPOSIT,
        }
      )
      const vaultAddress = await extractVaultAddress(tx)
      return EthRestakeBlocklistErc20Vault__factory.connect(
        vaultAddress,
        await ethers.provider.getSigner()
      )
    },
  }
}
