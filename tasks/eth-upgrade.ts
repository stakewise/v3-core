import fs from 'fs'
import '@openzeppelin/hardhat-upgrades/dist/type-extensions'
import { simulateDeployImpl } from '@openzeppelin/hardhat-upgrades/dist/utils'
import { task } from 'hardhat/config'
import { deployContract, encodeGovernorContractCall } from '../helpers/utils'
import { NETWORKS } from '../helpers/constants'
import { GovernorCall, NetworkConfig } from '../helpers/types'

const DEPLOYMENTS_DIR = 'deployments'

task('eth-upgrade', 'upgrades StakeWise for Ethereum').setAction(async (taskArgs, hre) => {
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
  const osTokenConfigAddress = deployment.OsTokenConfig
  const depositDataRegistryAddress = deployment.DepositDataRegistry
  const ethValidatorsCheckerAddress = deployment.EthValidatorsChecker
  const rewardSplitterFactoryAddress = deployment.RewardSplitterFactory
  const osTokenVaultEscrowAddress = deployment.EthOsTokenVaultEscrow
  const osTokenFlashLoansAddress = deployment.OsTokenFlashLoans

  // accumulate governor transaction
  const governorTransaction: GovernorCall[] = []
  const vaultUpgrades: Record<string, Record<string, string>> = {}
  const vaultsRegistry = await ethers.getContractAt('VaultsRegistry', vaultsRegistryAddress)

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
      osTokenVaultEscrowAddress,
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

    // add vault implementation updates
    const vault = await ethers.getContractAt('EthVault', vaultImplAddress)
    const vaultId = await vault.vaultId()
    if (!(vaultId in vaultUpgrades)) {
      vaultUpgrades[vaultId] = {}
    }
    const vaultVersion = await vault.version()
    vaultUpgrades[vaultId][vaultVersion.toString()] = vaultImplAddress

    // encode governor calls
    governorTransaction.push(
      await encodeGovernorContractCall(vaultsRegistry, 'addVaultImpl(address)', [vaultImplAddress])
    )
  }

  // Deploy EthGenesisVault implementation
  const constructorArgs = [
    keeperAddress,
    vaultsRegistryAddress,
    networkConfig.validatorsRegistry,
    osTokenVaultControllerAddress,
    osTokenConfigAddress,
    osTokenVaultEscrowAddress,
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

  // add vault implementation update
  const vault = await ethers.getContractAt('EthVault', genesisVaultImplAddress)
  const vaultId = await vault.vaultId()
  if (!(vaultId in vaultUpgrades)) {
    vaultUpgrades[vaultId] = {}
  }
  const vaultVersion = await vault.version()
  vaultUpgrades[vaultId][vaultVersion.toString()] = genesisVaultImplAddress

  // encode governor calls
  governorTransaction.push(
    await encodeGovernorContractCall(vaultsRegistry, 'addVaultImpl(address)', [
      genesisVaultImplAddress,
    ])
  )
  console.log(`NB! Upgrade EthGenesisVault to V4: ${genesisVaultImplAddress}`)

  // Save the addresses
  const addresses = {
    VaultsRegistry: vaultsRegistryAddress,
    Keeper: keeperAddress,
    DepositDataRegistry: depositDataRegistryAddress,
    EthValidatorsChecker: ethValidatorsCheckerAddress,
    EthGenesisVault: genesisVaultAddress,
    EthFoxVault: foxVaultAddress,
    EthVaultFactory: deployment.EthVaultFactory,
    EthPrivVaultFactory: deployment.EthPrivVaultFactory,
    EthBlocklistVaultFactory: deployment.EthBlocklistVaultFactory,
    EthErc20VaultFactory: deployment.EthErc20VaultFactory,
    EthPrivErc20VaultFactory: deployment.EthPrivErc20VaultFactory,
    EthBlocklistErc20VaultFactory: deployment.EthBlocklistErc20VaultFactory,
    SharedMevEscrow: sharedMevEscrowAddress,
    OsToken: osTokenAddress,
    OsTokenConfig: osTokenConfigAddress,
    OsTokenVaultController: osTokenVaultControllerAddress,
    EthOsTokenVaultEscrow: osTokenVaultEscrowAddress,
    OsTokenFlashLoans: osTokenFlashLoansAddress,
    PriceFeed: priceFeedAddress,
    RewardSplitterFactory: rewardSplitterFactoryAddress,
    CumulativeMerkleDrop: cumulativeMerkleDropAddress,
  }
  let json = JSON.stringify(addresses, null, 2)
  let fileName = `${DEPLOYMENTS_DIR}/${networkName}.json`

  if (!fs.existsSync(DEPLOYMENTS_DIR)) {
    fs.mkdirSync(DEPLOYMENTS_DIR)
  }

  // save addresses
  fs.writeFileSync(fileName, json, 'utf-8')
  console.log('Addresses saved to', fileName)

  // save governor transactions
  json = JSON.stringify(governorTransaction, null, 2)
  fileName = `${DEPLOYMENTS_DIR}/${networkName}-upgrade-v4-tx.json`
  fs.writeFileSync(fileName, json, 'utf-8')
  console.log('Governor transaction saved to', fileName)

  // save vault upgrades
  json = JSON.stringify(vaultUpgrades, null, 2)
  fileName = `${DEPLOYMENTS_DIR}/${networkName}-vault-v4-upgrades.json`
  fs.writeFileSync(fileName, json, 'utf-8')
  console.log('Vault upgrades saved to', fileName)
})
