import fs from 'fs'
import '@openzeppelin/hardhat-upgrades/dist/type-extensions'
import { simulateDeployImpl } from '@openzeppelin/hardhat-upgrades/dist/utils'
import { task } from 'hardhat/config'
import { deployContract } from '../helpers/utils'
import { NETWORKS } from '../helpers/constants'
import { NetworkConfig } from '../helpers/types'

const DEPLOYMENTS_DIR = 'deployments'

task('eth-upgrade', 'upgrades StakeWise V3 for Ethereum').setAction(async (taskArgs, hre) => {
  const ethers = hre.ethers
  const networkName = hre.network.name
  const networkConfig: NetworkConfig = NETWORKS[networkName]
  const deployer = await ethers.provider.getSigner()

  if (networkConfig.foxVault === undefined) {
    throw new Error('FoxVault config is missing')
  }

  // Create the signer for the mnemonic
  console.log('Upgrading StakeWise V3 for Ethereum to', networkName, 'from', deployer.address)

  const { default: deployment } = await import(`../${DEPLOYMENTS_DIR}/${networkName}.json`)

  // read addresses
  const vaultsRegistryAddress = deployment.VaultsRegistry
  const sharedMevEscrowAddress = deployment.SharedMevEscrow
  const osTokenAddress = deployment.OsToken
  const keeperAddress = deployment.Keeper
  const osTokenVaultControllerAddress = deployment.OsTokenVaultController
  const genesisVaultAddress = deployment.EthGenesisVault
  const foxVaultAddress = deployment.EthFoxVault
  const priceFeedAddress = deployment.PriceFeed
  const cumulativeMerkleDropAddress = deployment.CumulativeMerkleDrop

  // Deploy OsTokenConfig
  const osTokenConfig = await deployContract(
    hre,
    'OsTokenConfig',
    [
      networkConfig.governor,
      {
        redeemFromLtvPercent: networkConfig.redeemFromLtvPercent,
        redeemToLtvPercent: networkConfig.redeemToLtvPercent,
        liqThresholdPercent: networkConfig.liqThresholdPercent,
        liqBonusPercent: networkConfig.liqBonusPercent,
        ltvPercent: networkConfig.ltvPercent,
      },
      networkConfig.governor,
      networkConfig.governor,
    ],
    'contracts/tokens/OsTokenConfig.sol:OsTokenConfig'
  )
  const osTokenConfigAddress = await osTokenConfig.getAddress()

  // Deploy DepositDataRegistry
  const depositDataRegistry = await deployContract(
    hre,
    'DepositDataRegistry',
    [vaultsRegistryAddress],
    'contracts/validators/DepositDataRegistry.sol:DepositDataRegistry'
  )
  const depositDataRegistryAddress = await depositDataRegistry.getAddress()

  const factories: string[] = []
  for (const vaultType of [
    'EthVault',
    'EthPrivVault',
    'EthBlocklistVault',
    'EthErc20Vault',
    'EthPrivErc20Vault',
    'EthBlocklistErc20Vault',
  ]) {
    // Deploy Vault Implementation
    const constructorArgs = [
      keeperAddress,
      vaultsRegistryAddress,
      networkConfig.validatorsRegistry,
      osTokenVaultControllerAddress,
      osTokenConfigAddress,
      sharedMevEscrowAddress,
      depositDataRegistryAddress,
      networkConfig.exitedAssetsClaimDelay,
    ]
    const vaultImpl = await deployContract(
      hre,
      vaultType,
      constructorArgs,
      `contracts/vaults/ethereum/${vaultType}.sol:${vaultType}`
    )
    const vaultImplAddress = await vaultImpl.getAddress()
    await simulateDeployImpl(
      hre,
      await ethers.getContractFactory(vaultType),
      { constructorArgs },
      vaultImplAddress
    )

    // Deploy Vault Factory
    const vaultFactory = await deployContract(
      hre,
      'EthVaultFactory',
      [vaultImplAddress, vaultsRegistryAddress],
      'contracts/vaults/ethereum/EthVaultFactory.sol:EthVaultFactory'
    )
    const vaultFactoryAddress = await vaultFactory.getAddress()

    console.log(
      `NB! Remove V1 ${vaultType}Factory from VaultsRegistry: ${deployment[vaultType + 'Factory']}`
    )
    console.log(`NB! Add V2 ${vaultType}Factory to VaultsRegistry: ${vaultFactoryAddress}`)
    console.log(`NB! Add ${vaultType} V2 implementation to VaultsRegistry: ${vaultImplAddress}`)
    factories.push(vaultFactoryAddress)
  }

  // Deploy EthGenesisVault implementation
  let constructorArgs = [
    keeperAddress,
    vaultsRegistryAddress,
    networkConfig.validatorsRegistry,
    osTokenVaultControllerAddress,
    osTokenConfigAddress,
    sharedMevEscrowAddress,
    depositDataRegistryAddress,
    networkConfig.genesisVault.poolEscrow,
    networkConfig.genesisVault.rewardToken,
    networkConfig.exitedAssetsClaimDelay,
  ]
  const genesisVaultImpl = await deployContract(
    hre,
    'EthGenesisVault',
    constructorArgs,
    'contracts/vaults/ethereum/EthGenesisVault.sol:EthGenesisVault'
  )
  const genesisVaultImplAddress = await genesisVaultImpl.getAddress()
  const genesisVaultFactory = await ethers.getContractFactory('EthGenesisVault')
  await simulateDeployImpl(hre, genesisVaultFactory, { constructorArgs }, genesisVaultImplAddress)

  console.log('NB! Remove EthGenesisVault V1 implementation from VaultsRegistry')
  console.log(
    `NB! Add EthGenesisVault V2 implementation to VaultsRegistry ${genesisVaultImplAddress}`
  )
  console.log(`NB! Upgrade EthGenesisVault to V2: ${genesisVaultImplAddress}`)

  // Deploy EthFoxVault implementation
  constructorArgs = [
    keeperAddress,
    vaultsRegistryAddress,
    networkConfig.validatorsRegistry,
    sharedMevEscrowAddress,
    depositDataRegistryAddress,
    networkConfig.exitedAssetsClaimDelay,
  ]
  const foxVaultImpl = await deployContract(
    hre,
    'EthFoxVault',
    constructorArgs,
    'contracts/vaults/ethereum/custom/EthFoxVault.sol:EthFoxVault'
  )
  const foxVaultImplAddress = await foxVaultImpl.getAddress()
  const foxVaultFactory = await ethers.getContractFactory('EthFoxVault')
  await simulateDeployImpl(hre, foxVaultFactory, { constructorArgs }, foxVaultImplAddress)

  console.log('NB! Remove EthFoxVault V1 implementation from VaultsRegistry')
  console.log(`NB! Add EthFoxVault V2 implementation to VaultsRegistry ${foxVaultImplAddress}`)
  console.log(`NB! Upgrade EthFoxVault to V2: ${foxVaultImplAddress}`)

  // Deploy EigenPodOwner implementation
  const eigenPodOwnerImpl = await deployContract(hre, 'EigenPodOwner', [
    networkConfig.eigenPodManager,
    networkConfig.eigenDelegationManager,
    networkConfig.eigenDelayedWithdrawalRouter,
  ])
  const eigenPodOwnerImplAddress = await eigenPodOwnerImpl.getAddress()

  // Deploy restake vaults
  for (const vaultType of [
    'EthRestakeVault',
    'EthRestakePrivVault',
    'EthRestakeBlocklistVault',
    'EthRestakeErc20Vault',
    'EthRestakePrivErc20Vault',
    'EthRestakeBlocklistErc20Vault',
  ]) {
    // Deploy Vault Implementation
    const constructorArgs = [
      keeperAddress,
      vaultsRegistryAddress,
      networkConfig.validatorsRegistry,
      sharedMevEscrowAddress,
      depositDataRegistryAddress,
      eigenPodOwnerImplAddress,
      networkConfig.exitedAssetsClaimDelay,
    ]
    const vaultImpl = await deployContract(
      hre,
      vaultType,
      constructorArgs,
      `contracts/vaults/ethereum/restake/${vaultType}.sol:${vaultType}`
    )
    const vaultImplAddress = await vaultImpl.getAddress()
    await simulateDeployImpl(
      hre,
      await ethers.getContractFactory(vaultType),
      { constructorArgs },
      vaultImplAddress
    )

    // Deploy Vault Factory
    const vaultFactory = await deployContract(
      hre,
      'EthVaultFactory',
      [vaultImplAddress, vaultsRegistryAddress],
      'contracts/vaults/ethereum/EthVaultFactory.sol:EthVaultFactory'
    )
    const vaultFactoryAddress = await vaultFactory.getAddress()
    factories.push(vaultFactoryAddress)

    console.log(`NB! Add V2 ${vaultType}Factory to VaultsRegistry: ${vaultFactoryAddress}`)
  }

  // Deploy RewardSplitter Implementation
  const rewardSplitterImpl = await deployContract(
    hre,
    'RewardSplitter',
    [],
    'contracts/misc/RewardSplitter.sol:RewardSplitter'
  )
  const rewardSplitterImplAddress = await rewardSplitterImpl.getAddress()

  // Deploy RewardSplitter factory
  const rewardSplitterFactory = await deployContract(
    hre,
    'RewardSplitterFactory',
    [rewardSplitterImplAddress],
    'contracts/misc/RewardSplitterFactory.sol:RewardSplitterFactory'
  )
  const rewardSplitterFactoryAddress = await rewardSplitterFactory.getAddress()

  // Save the addresses
  const addresses = {
    VaultsRegistry: vaultsRegistryAddress,
    Keeper: keeperAddress,
    DepositDataRegistry: depositDataRegistryAddress,
    EthGenesisVault: genesisVaultAddress,
    EthFoxVault: foxVaultAddress,
    EthVaultFactory: factories[0],
    EthPrivVaultFactory: factories[1],
    EthBlocklistVaultFactory: factories[2],
    EthErc20VaultFactory: factories[3],
    EthPrivErc20VaultFactory: factories[4],
    EthBlocklistErc20VaultFactory: factories[5],
    EthRestakeVaultFactory: factories[6],
    EthRestakePrivVaultFactory: factories[7],
    EthRestakeBlocklistVaultFactory: factories[8],
    EthRestakeErc20VaultFactory: factories[9],
    EthRestakePrivErc20VaultFactory: factories[10],
    EthRestakeBlocklistErc20VaultFactory: factories[11],
    SharedMevEscrow: sharedMevEscrowAddress,
    OsToken: osTokenAddress,
    OsTokenConfig: osTokenConfigAddress,
    OsTokenVaultController: osTokenVaultControllerAddress,
    PriceFeed: priceFeedAddress,
    RewardSplitterFactory: rewardSplitterFactoryAddress,
    CumulativeMerkleDrop: cumulativeMerkleDropAddress,
  }
  const json = JSON.stringify(addresses, null, 2)
  const fileName = `${DEPLOYMENTS_DIR}/${networkName}.json`

  if (!fs.existsSync(DEPLOYMENTS_DIR)) {
    fs.mkdirSync(DEPLOYMENTS_DIR)
  }

  fs.writeFileSync(fileName, json, 'utf-8')
  console.log('Saved to', fileName)
})
