import '@nomiclabs/hardhat-ethers'
import fs from 'fs'
import '@openzeppelin/hardhat-upgrades/dist/type-extensions'
import { task } from 'hardhat/config'
import {
  Keeper__factory,
  EthVault__factory,
  EthPrivateVault__factory,
  EthVaultFactory__factory,
  Oracles__factory,
  VaultsRegistry__factory,
} from '../typechain-types'
import { deployContract } from '../helpers/utils'
import { NETWORKS } from '../helpers/constants'
import { NetworkConfig } from '../helpers/types'

const DEPLOYMENTS_DIR = 'deployments'
const FEE_DATA = {
  maxFeePerGas: '100000000000',
  maxPriorityFeePerGas: '5000000000',
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

  const vaultsRegistry = await deployContract(
    new VaultsRegistry__factory(deployer).deploy(networkConfig.governor)
  )
  console.log('VaultsRegistry deployed at', vaultsRegistry.address)

  const oracles = await deployContract(
    new Oracles__factory(deployer).deploy(
      networkConfig.governor,
      networkConfig.oracles,
      networkConfig.requiredOracles,
      networkConfig.oraclesConfigIpfsHash
    )
  )
  console.log('Oracles deployed at', oracles.address)

  const keeper = await upgrades.deployProxy(
    new Keeper__factory(deployer),
    [networkConfig.governor, networkConfig.rewardsDelay],
    {
      unsafeAllow: ['delegatecall'],
      constructorArgs: [oracles.address, vaultsRegistry.address, networkConfig.validatorsRegistry],
    }
  )
  await keeper.deployed()
  console.log('Keeper deployed at', keeper.address)

  const publicVaultImpl = await upgrades.deployImplementation(new EthVault__factory(deployer), {
    unsafeAllow: ['delegatecall'],
    constructorArgs: [keeper.address, vaultsRegistry.address, networkConfig.validatorsRegistry],
  })
  const privateVaultImpl = await upgrades.deployImplementation(
    new EthPrivateVault__factory(deployer),
    {
      unsafeAllow: ['delegatecall'],
      constructorArgs: [keeper.address, vaultsRegistry.address, networkConfig.validatorsRegistry],
    }
  )
  const ethVaultFactory = await deployContract(
    new EthVaultFactory__factory(deployer).deploy(
      publicVaultImpl as string,
      privateVaultImpl as string,
      vaultsRegistry.address
    )
  )
  console.log('EthVaultFactory deployed at', ethVaultFactory.address)

  // Save the addresses
  const addresses = {
    VaultsRegistry: vaultsRegistry.address,
    Oracles: oracles.address,
    Keeper: keeper.address,
    EthVaultFactory: ethVaultFactory.address,
  }
  const json = JSON.stringify(addresses, null, 2)
  const fileName = `${DEPLOYMENTS_DIR}/${networkName}.json`

  if (!fs.existsSync(DEPLOYMENTS_DIR)) {
    fs.mkdirSync(DEPLOYMENTS_DIR)
  }

  fs.writeFileSync(fileName, json, 'utf-8')
  console.log('Saved to', fileName)
})
