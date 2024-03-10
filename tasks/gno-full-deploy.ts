import fs from 'fs'
import '@openzeppelin/hardhat-upgrades/dist/type-extensions'
import { simulateDeployImpl } from '@openzeppelin/hardhat-upgrades/dist/utils'
import { task } from 'hardhat/config'
import { deployContract, callContract } from '../helpers/utils'
import { NETWORKS } from '../helpers/constants'
import { NetworkConfig } from '../helpers/types'

const DEPLOYMENTS_DIR = 'deployments'

task('gno-full-deploy', 'deploys StakeWise V3 for Gnosis').setAction(async (taskArgs, hre) => {
  const ethers = hre.ethers
  const networkName = hre.network.name
  const networkConfig: NetworkConfig = NETWORKS[networkName]
  const deployer = await ethers.provider.getSigner()

  if (networkConfig.gnosis === undefined) {
    throw new Error('Gnosis data is required for this network')
  }

  // Create the signer for the mnemonic, connected to the provider with hardcoded fee data
  console.log('Deploying StakeWise V3 for Gnosis to', networkName, 'from', deployer.address)

  // deploy VaultsRegistry
  const vaultsRegistry = await deployContract(
    hre,
    'VaultsRegistry',
    [],
    'contracts/vaults/VaultsRegistry.sol:VaultsRegistry'
  )
  const vaultsRegistryAddress = await vaultsRegistry.getAddress()

  // deploy SharedMevEscrow
  const sharedMevEscrow = await deployContract(
    hre,
    'GnoSharedMevEscrow',
    [vaultsRegistryAddress],
    'contracts/vaults/gnosis/mev/GnoSharedMevEscrow.sol:GnoSharedMevEscrow'
  )
  const sharedMevEscrowAddress = await sharedMevEscrow.getAddress()

  // calculate osToken and keeper addresses
  const osTokenAddress = ethers.getCreateAddress({
    from: deployer.address,
    nonce: (await ethers.provider.getTransactionCount(deployer.address)) + 1,
  })
  const keeperAddress = ethers.getCreateAddress({
    from: deployer.address,
    nonce: (await ethers.provider.getTransactionCount(deployer.address)) + 2,
  })

  // deploy OsTokenVaultController
  const osTokenVaultController = await deployContract(
    hre,
    'OsTokenVaultController',
    [
      keeperAddress,
      vaultsRegistryAddress,
      osTokenAddress,
      networkConfig.treasury,
      networkConfig.governor,
      networkConfig.osTokenFeePercent,
      networkConfig.osTokenCapacity,
    ],
    'contracts/osToken/OsTokenVaultController.sol:OsTokenVaultController'
  )
  const osTokenVaultControllerAddress = await osTokenVaultController.getAddress()

  // Deploy OsToken
  const osToken = await deployContract(
    hre,
    'OsToken',
    [
      networkConfig.governor,
      osTokenVaultControllerAddress,
      networkConfig.osTokenName,
      networkConfig.osTokenSymbol,
    ],
    'contracts/osToken/OsToken.sol:OsToken'
  )
  if ((await osToken.getAddress()) !== osTokenAddress) {
    throw new Error('OsToken address mismatch')
  }

  // Deploy Keeper
  const keeper = await deployContract(
    hre,
    'Keeper',
    [
      sharedMevEscrowAddress,
      vaultsRegistryAddress,
      osTokenVaultControllerAddress,
      networkConfig.rewardsDelay,
      networkConfig.maxAvgRewardPerSecond,
      networkConfig.validatorsRegistry,
    ],
    'contracts/keeper/Keeper.sol:Keeper'
  )
  if ((await keeper.getAddress()) !== keeperAddress) {
    throw new Error('Keeper address mismatch')
  }

  // Configure Keeper
  for (let i = 0; i < networkConfig.oracles.length; i++) {
    const oracleAddr = networkConfig.oracles[i]
    await callContract(keeper.addOracle(oracleAddr))
    console.log('Added oracle', oracleAddr)
  }
  await callContract(keeper.updateConfig(networkConfig.oraclesConfigIpfsHash))
  console.log('Updated oracles config to', networkConfig.oraclesConfigIpfsHash)

  await callContract(keeper.setRewardsMinOracles(networkConfig.rewardsMinOracles))
  console.log('Set rewards min oracles to', networkConfig.rewardsMinOracles)

  await callContract(keeper.setValidatorsMinOracles(networkConfig.validatorsMinOracles))
  console.log('Set validators min oracles to', networkConfig.validatorsMinOracles)

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
    ],
    'contracts/osToken/OsTokenConfig.sol:OsTokenConfig'
  )
  const osTokenConfigAddress = await osTokenConfig.getAddress()

  // Deploy XdaiExchange implementation
  const xdaiExchangeConstructorArgs = [
    networkConfig.gnosis.gnoToken,
    networkConfig.gnosis.balancerPoolId,
    networkConfig.gnosis.balancerVault,
    vaultsRegistryAddress,
  ]
  const xDaiExchangeImpl = await deployContract(
    hre,
    'XdaiExchange',
    xdaiExchangeConstructorArgs,
    'contracts/misc/XdaiExchange.sol:XdaiExchange'
  )
  const xDaiExchangeImplAddress = await xDaiExchangeImpl.getAddress()
  const xDaiExchangeFactory = await ethers.getContractFactory('XdaiExchange')
  await simulateDeployImpl(
    hre,
    xDaiExchangeFactory,
    { constructorArgs: xdaiExchangeConstructorArgs },
    xDaiExchangeImplAddress
  )

  // Deploy XdaiExchange proxy
  let proxy = await deployContract(
    hre,
    'ERC1967Proxy',
    [xDaiExchangeImplAddress, '0x'],
    '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy'
  )
  const xdaiExchangeAddress = await proxy.getAddress()
  const xdaiExchange = xDaiExchangeFactory.attach(xdaiExchangeAddress)

  // Initialize XdaiExchange
  await callContract(xdaiExchange.initialize(networkConfig.governor))

  const factories: string[] = []
  for (const vaultType of [
    'GnoVault',
    'GnoPrivVault',
    'GnoErc20Vault',
    'GnoBlocklistVault',
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
      sharedMevEscrowAddress,
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

    // Add factory to registry
    await callContract(vaultsRegistry.addFactory(vaultFactoryAddress))
    console.log(`Added ${vaultType}Factory to VaultsRegistry`)

    // Add implementation to registry
    await callContract(vaultsRegistry.addVaultImpl(vaultImplAddress))
    console.log(`Added ${vaultType} implementation to VaultsRegistry`)
    factories.push(vaultFactoryAddress)
  }

  // Deploy GnoGenesisVault implementation
  const genesisVaultConstructorArgs = [
    keeperAddress,
    vaultsRegistryAddress,
    networkConfig.validatorsRegistry,
    osTokenVaultControllerAddress,
    osTokenConfigAddress,
    sharedMevEscrowAddress,
    networkConfig.gnosis.gnoToken,
    xdaiExchangeAddress,
    networkConfig.genesisVault.poolEscrow,
    networkConfig.genesisVault.rewardToken,
    networkConfig.exitedAssetsClaimDelay,
  ]
  const genesisVaultImpl = await deployContract(
    hre,
    'GnoGenesisVault',
    genesisVaultConstructorArgs,
    'contracts/vaults/gnosis/GnoGenesisVault.sol:GnoGenesisVault'
  )
  const genesisVaultImplAddress = await genesisVaultImpl.getAddress()
  const genesisVaultFactory = await ethers.getContractFactory('GnoGenesisVault')
  await simulateDeployImpl(
    hre,
    genesisVaultFactory,
    { constructorArgs: genesisVaultConstructorArgs },
    genesisVaultImplAddress
  )

  // Deploy GnoGenesisVault proxy
  proxy = await deployContract(
    hre,
    'ERC1967Proxy',
    [genesisVaultImplAddress, '0x'],
    '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy'
  )
  const genesisVaultAddress = await proxy.getAddress()
  const genesisVault = genesisVaultFactory.attach(genesisVaultAddress)

  // Initialize GnoGenesisVault
  const erc20TokenFactory = await ethers.getContractFactory('ERC20Mock')
  const erc20Token = erc20TokenFactory.attach(networkConfig.gnosis.gnoToken)
  await callContract(erc20Token.approve(genesisVaultAddress, networkConfig.securityDeposit))
  await callContract(
    genesisVault.initialize(
      ethers.AbiCoder.defaultAbiCoder().encode(
        ['address', 'tuple(uint256 capacity, uint16 feePercent, string metadataIpfsHash)'],
        [
          networkConfig.genesisVault.admin,
          [networkConfig.genesisVault.capacity, networkConfig.genesisVault.feePercent, ''],
        ]
      )
    )
  )

  await callContract(vaultsRegistry.addVault(genesisVaultAddress))
  console.log('Added GnoGenesisVault to VaultsRegistry')

  await callContract(vaultsRegistry.addVaultImpl(genesisVaultImplAddress))
  console.log(`Added GnoGenesisVault implementation to VaultsRegistry`)

  // Deploy PriceFeed
  const priceFeed = await deployContract(
    hre,
    'PriceFeed',
    [osTokenVaultControllerAddress, networkConfig.priceFeedDescription],
    'contracts/osToken/PriceFeed.sol:PriceFeed'
  )
  const priceFeedAddress = await priceFeed.getAddress()

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

  // transfer ownership to governor
  await callContract(vaultsRegistry.initialize(networkConfig.governor))
  console.log('VaultsRegistry ownership transferred to', networkConfig.governor)

  await callContract(keeper.initialize(networkConfig.governor))
  console.log('Keeper ownership transferred to', networkConfig.governor)

  // Save the addresses
  const addresses = {
    VaultsRegistry: vaultsRegistryAddress,
    Keeper: keeperAddress,
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
    PriceFeed: priceFeedAddress,
    RewardSplitterFactory: rewardSplitterFactoryAddress,
  }
  const json = JSON.stringify(addresses, null, 2)
  const fileName = `${DEPLOYMENTS_DIR}/${networkName}.json`

  if (!fs.existsSync(DEPLOYMENTS_DIR)) {
    fs.mkdirSync(DEPLOYMENTS_DIR)
  }

  fs.writeFileSync(fileName, json, 'utf-8')
  console.log('Saved to', fileName)

  console.log('NB! Commit and accept StakeWise V2 PoolEscrow ownership to GnoGenesisVault')
})
