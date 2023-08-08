import '@nomiclabs/hardhat-ethers'
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
} from '../typechain-types'
import { deployContract, verify } from '../helpers/utils'
import { NETWORKS } from '../helpers/constants'
import { NetworkConfig } from '../helpers/types'
import { getContractAddress } from 'ethers/lib/utils'

const DEPLOYMENTS_DIR = 'deployments'
const FEE_DATA = {
  maxFeePerGas: '364053996066',
  maxPriorityFeePerGas: '305657672',
}

task('eth-full-deploy', 'deploys StakeWise V3 for Ethereum').setAction(async (taskArgs, hre) => {
  const upgrades = hre.upgrades
  const ethers = hre.ethers
  const networkName = hre.network.name
  const networkConfig: NetworkConfig = NETWORKS[networkName]

  // Wrap the provider so we can override fee data.
  const provider = new ethers.providers.FallbackProvider([ethers.provider], 1)
  provider.getFeeData = async () => FEE_DATA

  // Create the signer for the mnemonic, connected to the provider with hardcoded fee data
  const deployer = ethers.Wallet.fromMnemonic(process.env.MNEMONIC).connect(provider)

  const vaultsRegistry = await deployContract(new VaultsRegistry__factory(deployer).deploy())
  console.log('VaultsRegistry deployed at', vaultsRegistry.address)
  await verify(
    hre,
    vaultsRegistry.address,
    [],
    'contracts/vaults/VaultsRegistry.sol:VaultsRegistry'
  )

  const sharedMevEscrow = await deployContract(
    new SharedMevEscrow__factory(deployer).deploy(vaultsRegistry.address)
  )
  console.log('SharedMevEscrow deployed at', sharedMevEscrow.address)
  await verify(
    hre,
    sharedMevEscrow.address,
    [vaultsRegistry.address],
    'contracts/vaults/ethereum/mev/SharedMevEscrow.sol:SharedMevEscrow'
  )

  const keeperCalculatedAddress = getContractAddress({
    from: deployer.address,
    nonce: (await deployer.getTransactionCount()) + 1,
  })
  const osToken = await deployContract(
    new OsToken__factory(deployer).deploy(
      keeperCalculatedAddress,
      vaultsRegistry.address,
      networkConfig.treasury,
      networkConfig.osTokenFeePercent,
      networkConfig.osTokenCapacity,
      networkConfig.osTokenName,
      networkConfig.osTokenSymbol
    )
  )
  console.log('OsToken deployed at', osToken.address)
  await verify(
    hre,
    osToken.address,
    [
      keeperCalculatedAddress,
      vaultsRegistry.address,
      networkConfig.treasury,
      networkConfig.osTokenFeePercent,
      networkConfig.osTokenCapacity,
      networkConfig.osTokenName,
      networkConfig.osTokenSymbol,
    ],
    'contracts/osToken/OsToken.sol:OsToken'
  )

  const keeper = await deployContract(
    new Keeper__factory(deployer).deploy(
      sharedMevEscrow.address,
      vaultsRegistry.address,
      osToken.address,
      networkConfig.rewardsDelay,
      networkConfig.maxAvgRewardPerSecond,
      networkConfig.validatorsRegistry
    )
  )
  if (keeper.address !== keeperCalculatedAddress) {
    throw new Error('Keeper address mismatch')
  }
  console.log('Keeper deployed at', keeper.address)

  for (let i = 0; i < networkConfig.oracles.length; i++) {
    await keeper.addOracle(networkConfig.oracles[i])
  }
  await keeper.updateConfig(networkConfig.oraclesConfigIpfsHash)
  await keeper.setRewardsMinOracles(networkConfig.rewardsMinOracles)
  await keeper.setValidatorsMinOracles(networkConfig.validatorsMinOracles)
  await verify(
    hre,
    keeper.address,
    [
      sharedMevEscrow.address,
      vaultsRegistry.address,
      osToken.address,
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
  console.log('OsTokenConfig deployed at', osTokenConfig.address)
  await verify(
    hre,
    osTokenConfig.address,
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
        keeper.address,
        vaultsRegistry.address,
        networkConfig.validatorsRegistry,
        osToken.address,
        osTokenConfig.address,
        sharedMevEscrow.address,
      ],
    })) as string
    console.log(`${vaultType} implementation deployed at`, vaultImpl)
    await verify(
      hre,
      vaultImpl,
      [
        keeper.address,
        vaultsRegistry.address,
        networkConfig.validatorsRegistry,
        osToken.address,
        osTokenConfig.address,
        sharedMevEscrow.address,
      ],
      `contracts/vaults/ethereum/${vaultType}.sol:${vaultType}`
    )

    const ethVaultFactory = await deployContract(
      new EthVaultFactory__factory(deployer).deploy(vaultImpl, vaultsRegistry.address)
    )
    console.log(`${vaultType}Factory deployed at`, ethVaultFactory.address)
    await verify(
      hre,
      ethVaultFactory.address,
      [vaultImpl, vaultsRegistry.address],
      'contracts/vaults/ethereum/EthVaultFactory.sol:EthVaultFactory'
    )

    await vaultsRegistry.addFactory(ethVaultFactory.address)
    console.log(`Added ${vaultType}Factory to VaultsRegistry`)

    await osToken.setVaultImplementation(vaultImpl, true)
    console.log(`Added ${vaultType} implementation to OsToken`)
    factories.push(ethVaultFactory.address)
  }

  const ethGenesisVaultFactory = await ethers.getContractFactory('EthGenesisVault')
  const ethGenesisVault = await upgrades.deployProxy(ethGenesisVaultFactory, [], {
    unsafeAllow: ['delegatecall'],
    initializer: false,
    constructorArgs: [
      keeper.address,
      vaultsRegistry.address,
      networkConfig.validatorsRegistry,
      osToken.address,
      osTokenConfig.address,
      sharedMevEscrow.address,
      networkConfig.genesisVault.poolEscrow,
      networkConfig.genesisVault.stakedEthToken,
    ],
  })
  await ethGenesisVault.deployed()
  const tx = await ethGenesisVault.initialize(
    ethers.utils.defaultAbiCoder.encode(
      ['address', 'tuple(uint256 capacity, uint16 feePercent, string metadataIpfsHash)'],
      [
        networkConfig.genesisVault.admin,
        [networkConfig.genesisVault.capacity, networkConfig.genesisVault.feePercent, ''],
      ]
    ),
    { value: networkConfig.securityDeposit }
  )
  await tx.wait()
  console.log(`EthGenesisVault deployed at`, ethGenesisVault.address)

  await vaultsRegistry.addVault(ethGenesisVault.address)
  console.log('Added EthGenesisVault to VaultsRegistry')

  const ethGenesisVaultImpl = await ethGenesisVault.implementation()
  await osToken.setVaultImplementation(ethGenesisVaultImpl, true)
  console.log(`Added EthGenesisVault implementation to OsToken`)
  await verify(
    hre,
    ethGenesisVault.address,
    [
      keeper.address,
      vaultsRegistry.address,
      networkConfig.validatorsRegistry,
      osToken.address,
      osTokenConfig.address,
      sharedMevEscrow.address,
      networkConfig.genesisVault.poolEscrow,
      networkConfig.genesisVault.stakedEthToken,
    ],
    'contracts/vaults/ethereum/EthGenesisVault.sol:EthGenesisVault'
  )

  const priceFeed = await deployContract(
    new PriceFeed__factory(deployer).deploy(osToken.address, networkConfig.priceFeedDescription)
  )
  console.log('PriceFeed deployed at', priceFeed.address)
  await verify(
    hre,
    priceFeed.address,
    [osToken.address, networkConfig.priceFeedDescription],
    'contracts/osToken/PriceFeed.sol:PriceFeed'
  )

  // pass ownership to governor
  await vaultsRegistry.transferOwnership(networkConfig.governor)
  await keeper.transferOwnership(networkConfig.governor)
  await osToken.transferOwnership(networkConfig.governor)

  // Save the addresses
  const addresses = {
    VaultsRegistry: vaultsRegistry.address,
    Keeper: keeper.address,
    GenesisEthVault: ethGenesisVault.address,
    EthVaultFactory: factories[0],
    EthPrivVaultFactory: factories[1],
    EthErc20VaultFactory: factories[2],
    EthPrivErc20VaultFactory: factories[3],
    SharedMevEscrow: sharedMevEscrow.address,
    OsToken: osToken.address,
    OsTokenConfig: osTokenConfig.address,
    PriceFeed: priceFeed.address,
  }
  const json = JSON.stringify(addresses, null, 2)
  const fileName = `${DEPLOYMENTS_DIR}/${networkName}.json`

  if (!fs.existsSync(DEPLOYMENTS_DIR)) {
    fs.mkdirSync(DEPLOYMENTS_DIR)
  }

  fs.writeFileSync(fileName, json, 'utf-8')
  console.log('Saved to', fileName)

  console.log('NB! Accept ownership of Keeper from', networkConfig.governor)
  console.log('NB! Accept ownership of OsToken from', networkConfig.governor)
  console.log('NB! Accept ownership of VaultsRegistry from', networkConfig.governor)
  console.log('NB! Commit and accept StakeWise V2 PoolEscrow ownership to GenesisEthVault')
})
