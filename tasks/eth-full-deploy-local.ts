import fs from 'fs'
import '@openzeppelin/hardhat-upgrades/dist/type-extensions'
import { simulateDeployImpl } from '@openzeppelin/hardhat-upgrades/dist/utils'
import { task } from 'hardhat/config'
import { deployContract, callContract } from '../helpers/utils'
import EthValidatorsRegistry from '../test/shared/artifacts/EthValidatorsRegistry.json'
import { NetworkConfig, Networks } from '../helpers/types'
import { NETWORKS } from '../helpers/constants'

const DEPLOYMENTS_DIR = 'deployments'

task('eth-full-deploy-local', 'deploys StakeWise V3 for Ethereum to local network').setAction(
  async (taskArgs, hre) => {
    const ethers = hre.ethers
    const networkName = hre.network.name
    const networkConfig: NetworkConfig = NETWORKS[Networks.holesky]
    const accounts = await ethers.getSigners()
    const deployer = accounts[0]
    const governor = accounts[0]
    const treasury = accounts[1]
    const oracles = accounts.slice(2, 5)
    const rewardsMinOracles = 2
    const validatorsMinOracles = 2

    if (networkConfig.foxVault === undefined) {
      throw new Error('FoxVault config is missing')
    }

    // Create the signer for the mnemonic
    console.log('Deploying StakeWise V3 for Ethereum to', networkName, 'from', deployer.address)

    // deploy VaultsRegistry
    const vaultsRegistry = await deployContract(hre, 'VaultsRegistry', [])
    const vaultsRegistryAddress = await vaultsRegistry.getAddress()

    // deploy ValidatorsRegistry
    const validatorsRegistry = await (
      await ethers.getContractFactory(
        EthValidatorsRegistry.abi,
        EthValidatorsRegistry.bytecode,
        deployer
      )
    ).deploy()
    await validatorsRegistry.waitForDeployment()
    const validatorsRegistryAddress = await validatorsRegistry.getAddress()
    console.log('ValidatorsRegistry deployed at', validatorsRegistryAddress)

    // deploy SharedMevEscrow
    const sharedMevEscrow = await deployContract(hre, 'SharedMevEscrow', [vaultsRegistryAddress])
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
    const osTokenVaultController = await deployContract(hre, 'OsTokenVaultController', [
      keeperAddress,
      vaultsRegistryAddress,
      osTokenAddress,
      treasury,
      governor,
      networkConfig.osTokenFeePercent,
      networkConfig.osTokenCapacity,
    ])
    const osTokenVaultControllerAddress = await osTokenVaultController.getAddress()

    // Deploy OsToken
    const osToken = await deployContract(hre, 'OsToken', [
      governor,
      osTokenVaultControllerAddress,
      networkConfig.osTokenName,
      networkConfig.osTokenSymbol,
    ])
    if ((await osToken.getAddress()) !== osTokenAddress) {
      throw new Error('OsToken address mismatch')
    }

    // Deploy Keeper
    const keeper = await deployContract(hre, 'Keeper', [
      sharedMevEscrowAddress,
      vaultsRegistryAddress,
      osTokenVaultControllerAddress,
      networkConfig.rewardsDelay,
      networkConfig.maxAvgRewardPerSecond,
      validatorsRegistryAddress,
    ])
    if ((await keeper.getAddress()) !== keeperAddress) {
      throw new Error('Keeper address mismatch')
    }

    // Configure Keeper
    for (let i = 0; i < oracles.length; i++) {
      const oracleAddr = oracles[i].address
      await callContract(keeper.addOracle(oracleAddr))
      console.log('Added oracle', oracleAddr)
    }
    await callContract(keeper.updateConfig(networkConfig.oraclesConfigIpfsHash))
    console.log('Updated oracles config to', networkConfig.oraclesConfigIpfsHash)

    await callContract(keeper.setRewardsMinOracles(rewardsMinOracles))
    console.log('Set rewards min oracles to', rewardsMinOracles)

    await callContract(keeper.setValidatorsMinOracles(validatorsMinOracles))
    console.log('Set validators min oracles to', validatorsMinOracles)

    // Deploy OsTokenConfig
    const osTokenConfig = await deployContract(hre, 'OsTokenConfig', [
      governor.address,
      {
        liqThresholdPercent: networkConfig.liqThresholdPercent,
        liqBonusPercent: networkConfig.liqBonusPercent,
        ltvPercent: networkConfig.ltvPercent,
      },
      governor.address,
    ])
    const osTokenConfigAddress = await osTokenConfig.getAddress()

    // Deploy DepositDataRegistry
    const depositDataRegistry = await deployContract(hre, 'DepositDataRegistry', [
      vaultsRegistryAddress,
    ])
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
        validatorsRegistryAddress,
        osTokenVaultControllerAddress,
        osTokenConfigAddress,
        sharedMevEscrowAddress,
        depositDataRegistryAddress,
        networkConfig.exitedAssetsClaimDelay,
      ]
      const vaultImpl = await deployContract(hre, vaultType, constructorArgs)
      const vaultImplAddress = await vaultImpl.getAddress()
      await simulateDeployImpl(
        hre,
        await ethers.getContractFactory(vaultType),
        { constructorArgs },
        vaultImplAddress
      )

      // Deploy Vault Factory
      const vaultFactory = await deployContract(hre, 'EthVaultFactory', [
        vaultImplAddress,
        vaultsRegistryAddress,
      ])
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
      validatorsRegistryAddress,
      osTokenVaultControllerAddress,
      osTokenConfigAddress,
      sharedMevEscrowAddress,
      depositDataRegistryAddress,
      networkConfig.genesisVault.poolEscrow,
      networkConfig.genesisVault.rewardToken,
      networkConfig.exitedAssetsClaimDelay,
    ]
    const genesisVaultImpl = await deployContract(hre, 'EthGenesisVault', constructorArgs)
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
      undefined,
      { value: networkConfig.securityDeposit }
    )
    const genesisVaultAddress = await proxy.getAddress()

    await callContract(vaultsRegistry.addVault(genesisVaultAddress))
    console.log('Added EthGenesisVault to VaultsRegistry')

    await callContract(vaultsRegistry.addVaultImpl(genesisVaultImplAddress))
    console.log('Added EthGenesisVault implementation to VaultsRegistry')

    // Deploy EthFoxVault implementation
    constructorArgs = [
      keeperAddress,
      vaultsRegistryAddress,
      networkConfig.validatorsRegistry,
      sharedMevEscrowAddress,
      depositDataRegistryAddress,
      networkConfig.exitedAssetsClaimDelay,
    ]
    const foxVaultImpl = await deployContract(hre, 'EthFoxVault', constructorArgs)
    const foxVaultImplAddress = await foxVaultImpl.getAddress()
    const foxVaultFactory = await ethers.getContractFactory('EthFoxVault')
    await simulateDeployImpl(hre, foxVaultFactory, { constructorArgs }, foxVaultImplAddress)

    const foxVaultAddress = ethers.getCreateAddress({
      from: deployer.address,
      nonce: (await ethers.provider.getTransactionCount(deployer.address)) + 1,
    })

    // Deploy ownMevEscrow for EthFoxVault
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
      undefined,
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
        validatorsRegistryAddress,
        sharedMevEscrowAddress,
        depositDataRegistryAddress,
        eigenPodOwnerImplAddress,
        networkConfig.exitedAssetsClaimDelay,
      ]
      const vaultImpl = await deployContract(hre, vaultType, constructorArgs)
      const vaultImplAddress = await vaultImpl.getAddress()
      await simulateDeployImpl(
        hre,
        await ethers.getContractFactory(vaultType),
        { constructorArgs },
        vaultImplAddress
      )

      // Deploy Vault Factory
      const vaultFactory = await deployContract(hre, 'EthVaultFactory', [
        vaultImplAddress,
        vaultsRegistryAddress,
      ])
      const vaultFactoryAddress = await vaultFactory.getAddress()
      factories.push(vaultFactoryAddress)

      // Add factory to registry
      await callContract(vaultsRegistry.addFactory(vaultFactoryAddress))
      console.log(`Added ${vaultType}Factory to VaultsRegistry`)
    }

    // Deploy PriceFeed
    const priceFeed = await deployContract(hre, 'PriceFeed', [
      osTokenVaultControllerAddress,
      networkConfig.priceFeedDescription,
    ])
    const priceFeedAddress = await priceFeed.getAddress()

    // Deploy RewardSplitter Implementation
    const rewardSplitterImpl = await deployContract(hre, 'RewardSplitter', [])
    const rewardSplitterImplAddress = await rewardSplitterImpl.getAddress()

    // Deploy RewardSplitter factory
    const rewardSplitterFactory = await deployContract(hre, 'RewardSplitterFactory', [
      rewardSplitterImplAddress,
    ])
    const rewardSplitterFactoryAddress = await rewardSplitterFactory.getAddress()

    // Deploy CumulativeMerkleDrop
    const cumulativeMerkleDrop = await deployContract(hre, 'CumulativeMerkleDrop', [
      networkConfig.liquidityCommittee,
      networkConfig.swiseToken,
    ])
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

    console.log(
      'NB! EthGenesisVault is not configured properly as ' +
        'it requires StakeWise V2 tokens and PoolEscrow contracts'
    )
  }
)
