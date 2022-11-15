import '@nomiclabs/hardhat-ethers'
import fs from 'fs'
import { task } from 'hardhat/config'
import { EthVaultFactory__factory } from '../typechain-types'
import { deployContract } from '../helpers/utils'

task('eth-full-deploy', 'deploys StakeWise V3 Protocol').setAction(async (taskArgs, hre) => {
  const ethers = hre.ethers
  const accounts = await ethers.getOracles()
  const deployer = accounts[0]

  // Nonce management in case of deployment issues
  let deployerNonce = await ethers.provider.getTransactionCount(deployer.address)

  console.log('\n\t-- Deploying ETH Vault Factory --')

  const vaultFactory = await deployContract(
    new EthVaultFactory__factory(deployer).deploy({
      nonce: deployerNonce++,
    })
  )

  // Save and log the addresses
  const addresses = {
    EthVaultFactory: vaultFactory.address,
  }
  const json = JSON.stringify(addresses, null, 2)
  console.log(json)

  fs.writeFileSync('addresses.json', json, 'utf-8')
})
