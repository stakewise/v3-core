import '@nomiclabs/hardhat-ethers'
import fs from 'fs'
import { task } from 'hardhat/config'
import {
  EthKeeper__factory,
  EthVault__factory,
  EthVaultFactory__factory,
  Oracles__factory,
  Registry__factory,
} from '../typechain-types'
import { deployContract } from '../helpers/utils'
import { NETWORKS } from '../helpers/constants'
import { NetworkConfig } from '../helpers/types'

task('eth-full-deploy', 'deploys StakeWise V3 for Ethereum').setAction(async (taskArgs, hre) => {
  // @ts-ignore
  const upgrades = hre.upgrades
  const ethers = hre.ethers
  const accounts = await ethers.getSigners()
  const networkName = hre.network.name
  const networkConfig: NetworkConfig = NETWORKS[networkName]
  const deployer = accounts[0]
  console.log('Deploying from', deployer.address)

  const registry = await deployContract(
    new Registry__factory(deployer).deploy(networkConfig.governor)
  )
  console.log('Registry deployed at', registry.address)

  const oracles = await deployContract(
    new Oracles__factory(deployer).deploy(
      networkConfig.governor,
      networkConfig.oracles,
      networkConfig.requiredOracles
    )
  )
  console.log('Oracles deployed at', oracles.address)

  const keeper = await upgrades.deployProxy(
    new EthKeeper__factory(deployer),
    [networkConfig.governor],
    {
      unsafeAllow: ['delegatecall'],
      constructorArgs: [oracles.address, registry.address, networkConfig.validatorsRegistry],
    }
  )
  console.log('EthKeeper deployed at', keeper.address)

  const ethVaultImpl = await upgrades.deployImplementation(new EthVault__factory(deployer), {
    unsafeAllow: ['delegatecall'],
    constructorArgs: [keeper.address, registry.address, networkConfig.validatorsRegistry],
  })
  const ethVaultFactory = await deployContract(
    new EthVaultFactory__factory(deployer).deploy(ethVaultImpl as string, registry.address)
  )
  console.log('EthVaultFactory deployed at', ethVaultFactory.address)

  // Save the addresses
  const addresses = {
    Registry: registry.address,
    Oracles: oracles.address,
    EthKeeper: keeper.address,
    EthVaultFactory: ethVaultFactory.address,
  }
  const json = JSON.stringify(addresses, null, 2)
  const fileName = `${networkName}-addresses.json`
  fs.writeFileSync(fileName, json, 'utf-8')
  console.log('Saved to', fileName)
})
