import fs from 'fs'
import '@openzeppelin/hardhat-upgrades/dist/type-extensions'
import { simulateDeployImpl } from '@openzeppelin/hardhat-upgrades/dist/utils'
import { task } from 'hardhat/config'
import { deployContract, callContract } from '../helpers/utils'
import { NETWORKS } from '../helpers/constants'
import { NetworkConfig } from '../helpers/types'

const DEPLOYMENTS_DIR = 'deployments'

task('eth-full-deploy', 'deploys StakeWise V3 for Ethereum').setAction(async (taskArgs, hre) => {
  const ethers = hre.ethers
  const networkName = hre.network.name
  const networkConfig: NetworkConfig = NETWORKS[networkName]
  const deployer = await ethers.provider.getSigner()

  if (networkConfig.foxVault === undefined) {
    throw new Error('FoxVault config is missing')
  }

  // Create the signer for the mnemonic
  console.log('Deploying StakeWise V3 for Ethereum to', networkName, 'from', deployer.address)

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
    'SharedMevEscrow',
    [vaultsRegistryAddress],
    'contracts/vaults/ethereum/mev/SharedMevEscrow.sol:SharedMevEscrow'
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
    'contracts/tokens/OsTokenVaultController.sol:OsTokenVaultController'
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
    'contracts/tokens/OsToken.sol:OsToken'
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
        liqThresholdPercent: networkConfig.liqThresholdPercent,
        liqBonusPercent: networkConfig.liqBonusPercent,
        ltvPercent: networkConfig.ltvPercent,
      },
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

  // Deploy ValidatorsChecker
  const ethValidatorsChecker = await deployContract(
    hre,
    'EthValidatorsChecker',
    [
      networkConfig.validatorsRegistry,
      keeperAddress,
      vaultsRegistryAddress,
      depositDataRegistryAddress,
    ],
    'contracts/validators/EthValidatorsChecker.sol:EthValidatorsChecker'
  )
  const ethValidatorsCheckerAddress = await ethValidatorsChecker.getAddress()

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

    // Add factory to registry
    await callContract(vaultsRegistry.addFactory(vaultFactoryAddress))
    console.log(`Added ${vaultType}Factory to VaultsRegistry`)

    // Add implementation to registry
    await callContract(vaultsRegistry.addVaultImpl(vaultImplAddress))
    console.log(`Added ${vaultType} implementation to VaultsRegistry`)
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

  // Deploy and initialize EthGenesisVault proxy
  let initCall = ethers.AbiCoder.defaultAbiCoder().encode(
    ['address', 'tuple(uint256 capacity, uint16 feePercent, string metadataIpfsHash)'],
    [
      networkConfig.genesisVault.admin,
      [networkConfig.genesisVault.capacity, networkConfig.genesisVault.feePercent, ''],
    ]
  )
  let proxy = await deployContract(
    hre,
    'ERC1967Proxy',
    [
      genesisVaultImplAddress,
      genesisVaultFactory.interface.encodeFunctionData('initialize', [initCall]),
    ],
    '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy',
    { value: networkConfig.securityDeposit }
  )
  const genesisVaultAddress = await proxy.getAddress()

  await callContract(vaultsRegistry.addVault(genesisVaultAddress))
  console.log('Added EthGenesisVault to VaultsRegistry')

  await callContract(vaultsRegistry.addVaultImpl(genesisVaultImplAddress))
  console.log(`Added EthGenesisVault implementation to VaultsRegistry`)

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

  // calculate EthFoxVault address
  const foxVaultAddress = ethers.getCreateAddress({
    from: deployer.address,
    nonce: (await ethers.provider.getTransactionCount(deployer.address)) + 1,
  })

  // Deploy OwnMevEscrow for EthFoxVault
  const ownMevEscrowFactory = await ethers.getContractFactory('OwnMevEscrow')
  const ownMevEscrow = await ownMevEscrowFactory.deploy(foxVaultAddress)

  // Deploy and initialize EthFoxVault proxy
  initCall = ethers.AbiCoder.defaultAbiCoder().encode(
    [
      'tuple(address admin, address ownMevEscrow, uint256 capacity, uint16 feePercent, string metadataIpfsHash)',
    ],
    [
      [
        networkConfig.foxVault.admin,
        await ownMevEscrow.getAddress(),
        networkConfig.foxVault.capacity,
        networkConfig.foxVault.feePercent,
        networkConfig.foxVault.metadataIpfsHash,
      ],
    ]
  )

  proxy = await deployContract(
    hre,
    'ERC1967Proxy',
    [foxVaultImplAddress, foxVaultFactory.interface.encodeFunctionData('initialize', [initCall])],
    '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy',
    {
      value: networkConfig.securityDeposit,
    }
  )
  if ((await proxy.getAddress()) !== foxVaultAddress) {
    throw new Error('EthFoxVault address mismatch')
  }

  await callContract(vaultsRegistry.addVault(foxVaultAddress))
  console.log('Added EthFoxVault to VaultsRegistry')

  // Deploy EigenPodOwner implementation
  constructorArgs = [
    networkConfig.eigenPodManager,
    networkConfig.eigenDelegationManager,
    networkConfig.eigenDelayedWithdrawalRouter,
  ]
  const eigenPodOwnerImpl = await deployContract(
    hre,
    'EigenPodOwner',
    constructorArgs,
    'contracts/vaults/ethereum/restake/EigenPodOwner.sol:EigenPodOwner'
  )
  const eigenPodOwnerFactory = await ethers.getContractFactory('EigenPodOwner')
  const eigenPodOwnerImplAddress = await eigenPodOwnerImpl.getAddress()
  await simulateDeployImpl(hre, eigenPodOwnerFactory, { constructorArgs }, eigenPodOwnerImplAddress)

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

    // Deploy Restake Vault Factory
    const vaultFactory = await deployContract(
      hre,
      'EthRestakeVaultFactory',
      [networkConfig.governor, vaultImplAddress, vaultsRegistryAddress],
      'contracts/vaults/ethereum/restake/EthRestakeVaultFactory.sol:EthRestakeVaultFactory'
    )
    const vaultFactoryAddress = await vaultFactory.getAddress()
    factories.push(vaultFactoryAddress)

    // Add factory to registry
    await callContract(vaultsRegistry.addFactory(vaultFactoryAddress))
    console.log(`Added ${vaultType}Factory to VaultsRegistry`)
  }

  // Deploy PriceFeed
  const priceFeed = await deployContract(
    hre,
    'PriceFeed',
    [osTokenVaultControllerAddress, networkConfig.priceFeedDescription],
    'contracts/tokens/PriceFeed.sol:PriceFeed'
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

  // Deploy CumulativeMerkleDrop
  const cumulativeMerkleDrop = await deployContract(
    hre,
    'CumulativeMerkleDrop',
    [networkConfig.liquidityCommittee, networkConfig.swiseToken],
    'contracts/misc/CumulativeMerkleDrop.sol:CumulativeMerkleDrop'
  )
  const cumulativeMerkleDropAddress = await cumulativeMerkleDrop.getAddress()

  // transfer ownership to governor
  await callContract(vaultsRegistry.initialize(networkConfig.governor))
  console.log('VaultsRegistry ownership transferred to', networkConfig.governor)

  await callContract(keeper.initialize(networkConfig.governor))
  console.log('Keeper ownership transferred to', networkConfig.governor)

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

  // save addresses
  fs.writeFileSync(fileName, json, 'utf-8')
  console.log('Addresses saved to', fileName)

  console.log('NB! Commit and accept StakeWise V2 PoolEscrow ownership to EthGenesisVault')
})
