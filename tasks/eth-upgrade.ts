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

  // accumulate governor transaction
  const governorTransaction: GovernorCall[] = []
  const vaultUpgrades: Record<string, Record<string, string>> = {}
  const vaultsRegistry = await ethers.getContractAt('VaultsRegistry', vaultsRegistryAddress)
  const osToken = await ethers.getContractAt('OsToken', osTokenAddress)

  // Deploy EthOsTokenVaultEscrow
  const osTokenVaultEscrow = await deployContract(
    hre,
    'EthOsTokenVaultEscrow',
    [
      osTokenVaultControllerAddress,
      osTokenConfigAddress,
      networkConfig.governor,
      networkConfig.osTokenVaultEscrow.authenticator,
      networkConfig.osTokenVaultEscrow.liqThresholdPercent,
      networkConfig.osTokenVaultEscrow.liqBonusPercent,
    ],
    'contracts/tokens/EthOsTokenVaultEscrow.sol:EthOsTokenVaultEscrow'
  )
  const osTokenVaultEscrowAddress = await osTokenVaultEscrow.getAddress()

  // encode governor call to add escrow to the vaults registry
  governorTransaction.push(
    await encodeGovernorContractCall(vaultsRegistry, 'addVault(address)', [
      osTokenVaultEscrowAddress,
    ])
  )

  // Deploy OsTokenFlashLoans
  const osTokenFlashLoans = await deployContract(
    hre,
    'OsTokenFlashLoans',
    [osTokenAddress],
    'contracts/tokens/OsTokenFlashLoans.sol:OsTokenFlashLoans'
  )
  const osTokenFlashLoansAddress = await osTokenFlashLoans.getAddress()

  // encode governor call to add OsTokenFlashLoans as the OsToken controller
  governorTransaction.push(
    await encodeGovernorContractCall(osToken, 'setController(address,bool)', [
      osTokenFlashLoansAddress,
      true,
    ])
  )

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

    // Deploy Vault Factory
    const vaultFactory = await deployContract(
      hre,
      'EthVaultFactory',
      [vaultImplAddress, vaultsRegistryAddress],
      'contracts/vaults/ethereum/EthVaultFactory.sol:EthVaultFactory'
    )
    const vaultFactoryAddress = await vaultFactory.getAddress()
    factories.push(vaultFactoryAddress)

    // add vault implementation updates
    const vaultId = await vaultImpl.vaultId()
    if (!(vaultId in vaultUpgrades)) {
      vaultUpgrades[vaultId] = {}
    }
    const vaultVersion = await vaultImpl.version()
    vaultUpgrades[vaultId][vaultVersion.toString()] = vaultImplAddress

    // encode governor calls
    if (vaultType + 'Factory' in deployment) {
      governorTransaction.push(
        await encodeGovernorContractCall(vaultsRegistry, 'removeFactory(address)', [
          deployment[vaultType + 'Factory'],
        ])
      )
    }
    governorTransaction.push(
      await encodeGovernorContractCall(vaultsRegistry, 'addFactory(address)', [vaultFactoryAddress])
    )
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
  const vaultId = await genesisVaultImpl.vaultId()
  if (!(vaultId in vaultUpgrades)) {
    vaultUpgrades[vaultId] = {}
  }
  const vaultVersion = await genesisVaultImpl.version()
  vaultUpgrades[vaultId][vaultVersion.toString()] = genesisVaultImplAddress

  // encode governor calls
  governorTransaction.push(
    await encodeGovernorContractCall(vaultsRegistry, 'addVaultImpl(address)', [
      genesisVaultImplAddress,
    ])
  )
  console.log(`NB! Upgrade EthGenesisVault to V3: ${genesisVaultImplAddress}`)

  // Save the addresses
  const addresses = {
    VaultsRegistry: vaultsRegistryAddress,
    Keeper: keeperAddress,
    DepositDataRegistry: depositDataRegistryAddress,
    EthValidatorsChecker: ethValidatorsCheckerAddress,
    EthGenesisVault: genesisVaultAddress,
    EthFoxVault: foxVaultAddress,
    EthVaultFactory: factories[0],
    EthPrivVaultFactory: factories[1],
    EthBlocklistVaultFactory: factories[2],
    EthErc20VaultFactory: factories[3],
    EthPrivErc20VaultFactory: factories[4],
    EthBlocklistErc20VaultFactory: factories[5],
    SharedMevEscrow: sharedMevEscrowAddress,
    OsToken: osTokenAddress,
    OsTokenConfig: osTokenConfigAddress,
    OsTokenVaultController: osTokenVaultControllerAddress,
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
  fileName = `${DEPLOYMENTS_DIR}/${networkName}-v3-upgrade-tx.json`
  fs.writeFileSync(fileName, json, 'utf-8')
  console.log('Governor transaction saved to', fileName)

  // save vault upgrades
  json = JSON.stringify(vaultUpgrades, null, 2)
  fileName = `${DEPLOYMENTS_DIR}/${networkName}-v3-vault-upgrades.json`
  fs.writeFileSync(fileName, json, 'utf-8')
  console.log('Vault upgrades saved to', fileName)
})
