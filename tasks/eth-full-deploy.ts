import fs from 'fs'
import '@openzeppelin/hardhat-upgrades/dist/type-extensions'
import { task } from 'hardhat/config'
import {
  EthVaultFactory__factory,
  Keeper__factory,
  OsToken__factory,
  OsTokenConfig__factory,
  PriceFeed__factory,
  SharedMevEscrow__factory,
  VaultsRegistry__factory,
  RewardSplitter__factory,
  RewardSplitterFactory__factory,
  CumulativeMerkleDrop__factory,
  OsTokenChecker__factory,
} from '../typechain-types'
import { deployContract, verify } from '../helpers/utils'
import { NETWORKS } from '../helpers/constants'
import { NetworkConfig } from '../helpers/types'

const DEPLOYMENTS_DIR = 'deployments'

task('eth-full-deploy', 'deploys StakeWise V3 for Ethereum').setAction(async (taskArgs, hre) => {
  const upgrades = hre.upgrades
  const ethers = hre.ethers
  const networkName = hre.network.name
  const networkConfig: NetworkConfig = NETWORKS[networkName]

  // Create the signer for the mnemonic, connected to the provider with hardcoded fee data
  const deployer = ethers.Wallet.fromPhrase(process.env.MNEMONIC as string).connect(ethers.provider)

  const vaultsRegistry = await deployContract(new VaultsRegistry__factory(deployer).deploy())
  const vaultsRegistryAddress = await vaultsRegistry.getAddress()
  console.log('VaultsRegistry deployed at', vaultsRegistryAddress)
  await verify(hre, vaultsRegistryAddress, [], 'contracts/vaults/VaultsRegistry.sol:VaultsRegistry')

  const sharedMevEscrow = await deployContract(
    new SharedMevEscrow__factory(deployer).deploy(vaultsRegistryAddress)
  )
  const sharedMevEscrowAddress = await sharedMevEscrow.getAddress()
  console.log('SharedMevEscrow deployed at', sharedMevEscrowAddress)
  await verify(
    hre,
    sharedMevEscrowAddress,
    [vaultsRegistryAddress],
    'contracts/vaults/ethereum/mev/SharedMevEscrow.sol:SharedMevEscrow'
  )

  const osTokenChecker = await deployContract(
    new OsTokenChecker__factory(deployer).deploy(vaultsRegistryAddress)
  )
  const osTokenCheckerAddress = await osTokenChecker.getAddress()
  console.log('OsTokenChecker deployed at', osTokenCheckerAddress)
  await verify(
    hre,
    osTokenCheckerAddress,
    [vaultsRegistryAddress],
    'contracts/osToken/OsTokenChecker.sol:OsTokenChecker'
  )

  const keeperCalculatedAddress = ethers.getCreateAddress({
    from: deployer.address,
    nonce: (await ethers.provider.getTransactionCount(deployer.address)) + 1,
  })
  const osToken = await deployContract(
    new OsToken__factory(deployer).deploy(
      keeperCalculatedAddress,
      osTokenCheckerAddress,
      networkConfig.treasury,
      networkConfig.governor,
      networkConfig.osTokenFeePercent,
      networkConfig.osTokenCapacity,
      networkConfig.osTokenName,
      networkConfig.osTokenSymbol
    )
  )
  const osTokenAddress = await osToken.getAddress()
  console.log('OsToken deployed at', osTokenAddress)
  await verify(
    hre,
    osTokenAddress,
    [
      keeperCalculatedAddress,
      osTokenCheckerAddress,
      networkConfig.treasury,
      networkConfig.governor,
      networkConfig.osTokenFeePercent,
      networkConfig.osTokenCapacity,
      networkConfig.osTokenName,
      networkConfig.osTokenSymbol,
    ],
    'contracts/osToken/OsToken.sol:OsToken'
  )

  const keeper = await deployContract(
    new Keeper__factory(deployer).deploy(
      sharedMevEscrowAddress,
      vaultsRegistryAddress,
      osTokenAddress,
      networkConfig.rewardsDelay,
      networkConfig.maxAvgRewardPerSecond,
      networkConfig.validatorsRegistry
    )
  )
  const keeperAddress = await keeper.getAddress()
  if (keeperAddress !== keeperCalculatedAddress) {
    throw new Error('Keeper address mismatch')
  }
  console.log('Keeper deployed at', keeperAddress)

  for (let i = 0; i < networkConfig.oracles.length; i++) {
    await keeper.addOracle(networkConfig.oracles[i])
  }
  await keeper.updateConfig(networkConfig.oraclesConfigIpfsHash)
  await keeper.setRewardsMinOracles(networkConfig.rewardsMinOracles)
  await keeper.setValidatorsMinOracles(networkConfig.validatorsMinOracles)
  await verify(
    hre,
    keeperAddress,
    [
      sharedMevEscrowAddress,
      vaultsRegistryAddress,
      osTokenAddress,
      networkConfig.rewardsDelay,
      networkConfig.maxAvgRewardPerSecond,
      networkConfig.validatorsRegistry,
    ],
    'contracts/keeper/Keeper.sol:Keeper'
  )

  const osTokenConfig = await deployContract(
    new OsTokenConfig__factory(deployer).deploy(networkConfig.governor, {
      redeemFromLtvPercent: networkConfig.redeemFromLtvPercent,
      redeemToLtvPercent: networkConfig.redeemToLtvPercent,
      liqThresholdPercent: networkConfig.liqThresholdPercent,
      liqBonusPercent: networkConfig.liqBonusPercent,
      ltvPercent: networkConfig.ltvPercent,
    })
  )
  const osTokenConfigAddress = await osTokenConfig.getAddress()
  console.log('OsTokenConfig deployed at', osTokenConfigAddress)
  await verify(
    hre,
    osTokenConfigAddress,
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

  const factories: string[] = []
  for (const vaultType of ['EthVault', 'EthPrivVault', 'EthErc20Vault', 'EthPrivErc20Vault']) {
    const vault = await ethers.getContractFactory(vaultType)
    const vaultImpl = (await upgrades.deployImplementation(vault, {
      unsafeAllow: ['delegatecall'],
      constructorArgs: [
        keeperAddress,
        vaultsRegistryAddress,
        networkConfig.validatorsRegistry,
        osTokenAddress,
        osTokenConfigAddress,
        sharedMevEscrowAddress,
        networkConfig.exitedAssetsClaimDelay,
      ],
    })) as string
    console.log(`${vaultType} implementation deployed at`, vaultImpl)
    await verify(
      hre,
      vaultImpl,
      [
        keeperAddress,
        vaultsRegistryAddress,
        networkConfig.validatorsRegistry,
        osTokenAddress,
        osTokenConfigAddress,
        sharedMevEscrowAddress,
        networkConfig.exitedAssetsClaimDelay,
      ],
      `contracts/vaults/ethereum/${vaultType}.sol:${vaultType}`
    )

    const ethVaultFactory = await deployContract(
      new EthVaultFactory__factory(deployer).deploy(vaultImpl, vaultsRegistryAddress)
    )
    const ethVaultFactoryAddress = await ethVaultFactory.getAddress()
    console.log(`${vaultType}Factory deployed at`, ethVaultFactoryAddress)
    await verify(
      hre,
      ethVaultFactoryAddress,
      [vaultImpl, vaultsRegistryAddress],
      'contracts/vaults/ethereum/EthVaultFactory.sol:EthVaultFactory'
    )

    await vaultsRegistry.addFactory(ethVaultFactoryAddress)
    console.log(`Added ${vaultType}Factory to VaultsRegistry`)

    await vaultsRegistry.addVaultImpl(vaultImpl)
    console.log(`Added ${vaultType} implementation to VaultsRegistry`)
    factories.push(ethVaultFactoryAddress)
  }

  const ethGenesisVaultFactory = await ethers.getContractFactory('EthGenesisVault')
  const ethGenesisVault = await upgrades.deployProxy(ethGenesisVaultFactory, [], {
    unsafeAllow: ['delegatecall'],
    initializer: false,
    constructorArgs: [
      keeperAddress,
      vaultsRegistryAddress,
      networkConfig.validatorsRegistry,
      osTokenAddress,
      osTokenConfigAddress,
      sharedMevEscrowAddress,
      networkConfig.genesisVault.poolEscrow,
      networkConfig.genesisVault.rewardEthToken,
      networkConfig.exitedAssetsClaimDelay,
    ],
  })
  const ethGenesisVaultAddress = await ethGenesisVault.getAddress()
  await ethGenesisVault.waitForDeployment()
  const tx = await ethGenesisVault.initialize(
    ethers.AbiCoder.defaultAbiCoder().encode(
      ['address', 'tuple(uint256 capacity, uint16 feePercent, string metadataIpfsHash)'],
      [
        networkConfig.genesisVault.admin,
        [networkConfig.genesisVault.capacity, networkConfig.genesisVault.feePercent, ''],
      ]
    ),
    { value: networkConfig.securityDeposit }
  )
  await tx.wait()
  console.log(`EthGenesisVault deployed at`, ethGenesisVaultAddress)

  await vaultsRegistry.addVault(ethGenesisVaultAddress)
  console.log('Added EthGenesisVault to VaultsRegistry')

  const ethGenesisVaultImpl = await ethGenesisVault.implementation()
  await vaultsRegistry.addVaultImpl(ethGenesisVaultImpl)
  console.log(`Added EthGenesisVault implementation to VaultsRegistry`)
  await verify(
    hre,
    ethGenesisVaultAddress,
    [
      keeperAddress,
      vaultsRegistryAddress,
      networkConfig.validatorsRegistry,
      osTokenAddress,
      osTokenConfigAddress,
      sharedMevEscrowAddress,
      networkConfig.genesisVault.poolEscrow,
      networkConfig.genesisVault.rewardEthToken,
      networkConfig.exitedAssetsClaimDelay,
    ],
    'contracts/vaults/ethereum/EthGenesisVault.sol:EthGenesisVault'
  )

  const priceFeed = await deployContract(
    new PriceFeed__factory(deployer).deploy(osTokenAddress, networkConfig.priceFeedDescription)
  )
  const priceFeedAddress = await priceFeed.getAddress()
  console.log('PriceFeed deployed at', priceFeedAddress)
  await verify(
    hre,
    priceFeedAddress,
    [osTokenAddress, networkConfig.priceFeedDescription],
    'contracts/osToken/PriceFeed.sol:PriceFeed'
  )

  const rewardSplitterImpl = await deployContract(new RewardSplitter__factory(deployer).deploy())
  const rewardSplitterImplAddress = await rewardSplitterImpl.getAddress()
  console.log('RewardSplitter implementation deployed at', rewardSplitterImplAddress)
  await verify(
    hre,
    rewardSplitterImplAddress,
    [],
    'contracts/misc/RewardSplitter.sol:RewardSplitter'
  )

  const rewardSplitterFactory = await deployContract(
    new RewardSplitterFactory__factory(deployer).deploy(rewardSplitterImplAddress)
  )
  const rewardSplitterFactoryAddress = await rewardSplitterFactory.getAddress()
  console.log('RewardSplitterFactory deployed at', rewardSplitterFactoryAddress)
  await verify(
    hre,
    rewardSplitterFactoryAddress,
    [rewardSplitterImpl],
    'contracts/misc/RewardSplitterFactory.sol:RewardSplitterFactory'
  )

  const cumulativeMerkleDrop = await deployContract(
    new CumulativeMerkleDrop__factory(deployer).deploy(
      networkConfig.liquidityCommittee,
      networkConfig.swiseToken
    )
  )
  const cumulativeMerkleDropAddress = await cumulativeMerkleDrop.getAddress()
  console.log('CumulativeMerkleDrop deployed at', cumulativeMerkleDropAddress)
  await verify(
    hre,
    cumulativeMerkleDropAddress,
    [networkConfig.liquidityCommittee, networkConfig.swiseToken],
    'contracts/misc/CumulativeMerkleDrop.sol:CumulativeMerkleDrop'
  )

  // transfer ownership to governor
  await vaultsRegistry.initialize(networkConfig.governor)
  console.log('VaultsRegistry ownership transferred to', networkConfig.governor)

  await keeper.initialize(networkConfig.governor)
  console.log('Keeper ownership transferred to', networkConfig.governor)

  // Save the addresses
  const addresses = {
    VaultsRegistry: vaultsRegistryAddress,
    Keeper: keeperAddress,
    EthGenesisVault: ethGenesisVaultAddress,
    EthVaultFactory: factories[0],
    EthPrivVaultFactory: factories[1],
    EthErc20VaultFactory: factories[2],
    EthPrivErc20VaultFactory: factories[3],
    SharedMevEscrow: sharedMevEscrowAddress,
    OsToken: osTokenAddress,
    OsTokenConfig: osTokenConfigAddress,
    OsTokenChecker: osTokenCheckerAddress,
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

  console.log('NB! Commit and accept StakeWise V2 PoolEscrow ownership to EthGenesisVault')
})
