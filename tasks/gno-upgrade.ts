import fs from 'fs'
import '@openzeppelin/hardhat-upgrades/dist/type-extensions'
import { simulateDeployImpl } from '@openzeppelin/hardhat-upgrades/dist/utils'
import { task } from 'hardhat/config'
import { deployContract, encodeGovernorContractCall } from '../helpers/utils'
import { NETWORKS } from '../helpers/constants'
import { GovernorCall, NetworkConfig } from '../helpers/types'

const DEPLOYMENTS_DIR = 'deployments'

task('gno-upgrade', 'upgrades StakeWise for Gnosis').setAction(async (taskArgs, hre) => {
  const ethers = hre.ethers
  const networkName = hre.network.name
  const networkConfig: NetworkConfig = NETWORKS[networkName]
  const deployer = await ethers.provider.getSigner()

  if (networkConfig.gnosis === undefined) {
    throw new Error('Gnosis data is required for this network')
  }

  // Create the signer for the mnemonic
  console.log('Upgrading StakeWise V3 for Gnosis to', networkName, 'from', deployer.address)

  const { default: deployment } = await import(`../${DEPLOYMENTS_DIR}/${networkName}.json`)

  // read addresses
  const vaultsRegistryAddress = deployment.VaultsRegistry
  const keeperAddress = deployment.Keeper
  const depositDataRegistryAddress = deployment.DepositDataRegistry
  const gnoValidatorsCheckerAddress = deployment.GnoValidatorsChecker
  const xdaiExchangeAddress = deployment.XdaiExchange
  const genesisVaultAddress = deployment.GnoGenesisVault
  const sharedMevEscrowAddress = deployment.SharedMevEscrow
  const osTokenAddress = deployment.OsToken
  const osTokenConfigAddress = deployment.OsTokenConfig
  const osTokenVaultControllerAddress = deployment.OsTokenVaultController
  const priceFeedAddress = deployment.PriceFeed
  const rewardSplitterFactoryAddress = deployment.RewardSplitterFactory

  // accumulate governor transaction
  const governorTransaction: GovernorCall[] = []
  const vaultUpgrades: Record<string, Record<string, string>> = {}
  const vaultsRegistry = await ethers.getContractAt('VaultsRegistry', vaultsRegistryAddress)
  const osToken = await ethers.getContractAt('OsToken', osTokenAddress)

  // Deploy GnoOsTokenVaultEscrow
  const osTokenVaultEscrow = await deployContract(
    hre,
    'GnoOsTokenVaultEscrow',
    [
      osTokenVaultControllerAddress,
      osTokenConfigAddress,
      networkConfig.governor,
      networkConfig.osTokenVaultEscrow.authenticator,
      networkConfig.osTokenVaultEscrow.liqThresholdPercent,
      networkConfig.osTokenVaultEscrow.liqBonusPercent,
      networkConfig.gnosis.gnoToken,
    ],
    'contracts/tokens/GnoOsTokenVaultEscrow.sol:GnoOsTokenVaultEscrow'
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
    'GnoVault',
    'GnoPrivVault',
    'GnoBlocklistVault',
    'GnoErc20Vault',
    'GnoPrivErc20Vault',
    'GnoBlocklistErc20Vault',
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
      networkConfig.gnosis.gnoToken,
      xdaiExchangeAddress,
      networkConfig.exitedAssetsClaimDelay,
    ]
    const vaultImpl = await deployContract(
      hre,
      vaultType,
      constructorArgs,
      `contracts/vaults/gnosis/${vaultType}.sol:${vaultType}`
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
      'GnoVaultFactory',
      [vaultImplAddress, vaultsRegistryAddress, networkConfig.gnosis.gnoToken],
      'contracts/vaults/gnosis/GnoVaultFactory.sol:GnoVaultFactory'
    )
    const vaultFactoryAddress = await vaultFactory.getAddress()
    factories.push(vaultFactoryAddress)

    // add vault implementation updates
    const vault = await ethers.getContractAt('GnoVault', vaultImplAddress)
    const vaultId = await vault.vaultId()
    if (!(vaultId in vaultUpgrades)) {
      vaultUpgrades[vaultId] = {}
    }
    const vaultVersion = await vault.version()
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

  // Deploy GnoGenesisVault implementation
  const constructorArgs = [
    keeperAddress,
    vaultsRegistryAddress,
    networkConfig.validatorsRegistry,
    osTokenVaultControllerAddress,
    osTokenConfigAddress,
    osTokenVaultEscrowAddress,
    sharedMevEscrowAddress,
    depositDataRegistryAddress,
    networkConfig.gnosis.gnoToken,
    xdaiExchangeAddress,
    networkConfig.genesisVault.poolEscrow,
    networkConfig.genesisVault.rewardToken,
    networkConfig.exitedAssetsClaimDelay,
  ]
  const genesisVaultImpl = await deployContract(
    hre,
    'GnoGenesisVault',
    constructorArgs,
    'contracts/vaults/gnosis/GnoGenesisVault.sol:GnoGenesisVault'
  )
  const genesisVaultImplAddress = await genesisVaultImpl.getAddress()
  const genesisVaultFactory = await ethers.getContractFactory('GnoGenesisVault')
  await simulateDeployImpl(hre, genesisVaultFactory, { constructorArgs }, genesisVaultImplAddress)

  // add vault implementation update
  const vault = await ethers.getContractAt('GnoVault', genesisVaultImplAddress)
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
  console.log(`NB! Upgrade GnoGenesisVault to V3: ${genesisVaultImplAddress}`)

  // Save the addresses
  const addresses = {
    VaultsRegistry: vaultsRegistryAddress,
    Keeper: keeperAddress,
    DepositDataRegistry: depositDataRegistryAddress,
    GnoValidatorsChecker: gnoValidatorsCheckerAddress,
    XdaiExchange: xdaiExchangeAddress,
    GnoGenesisVault: genesisVaultAddress,
    GnoVaultFactory: factories[0],
    GnoPrivVaultFactory: factories[1],
    GnoBlocklistVaultFactory: factories[2],
    GnoErc20VaultFactory: factories[3],
    GnoPrivErc20VaultFactory: factories[4],
    GnoBlocklistErc20VaultFactory: factories[5],
    SharedMevEscrow: sharedMevEscrowAddress,
    OsToken: osTokenAddress,
    OsTokenConfig: osTokenConfigAddress,
    OsTokenVaultController: osTokenVaultControllerAddress,
    GnoOsTokenVaultEscrow: osTokenVaultEscrowAddress,
    OsTokenFlashLoans: osTokenFlashLoansAddress,
    PriceFeed: priceFeedAddress,
    RewardSplitterFactory: rewardSplitterFactoryAddress,
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
  fileName = `${DEPLOYMENTS_DIR}/${networkName}-upgrade-v3-tx.json`
  fs.writeFileSync(fileName, json, 'utf-8')
  console.log('Governor transaction saved to', fileName)

  // save vault upgrades
  json = JSON.stringify(vaultUpgrades, null, 2)
  fileName = `${DEPLOYMENTS_DIR}/${networkName}-vault-v3-upgrades.json`
  fs.writeFileSync(fileName, json, 'utf-8')
  console.log('Vault upgrades saved to', fileName)
})
