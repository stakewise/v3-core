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
import { deployContract } from '../helpers/utils'
import { getContractAddress } from 'ethers/lib/utils'
import { NetworkConfig, Networks } from '../helpers/types'
import { ethValidatorsRegistry, NETWORKS } from '../helpers/constants'

const DEPLOYMENTS_DIR = 'deployments'

task('eth-full-deploy-local', 'deploys StakeWise V3 for Ethereum to local network').setAction(
  async (taskArgs, hre) => {
    const upgrades = hre.upgrades
    const ethers = hre.ethers
    const networkName = hre.network.name
    const goerliConfig: NetworkConfig = NETWORKS[Networks.goerli]
    const accounts = await ethers.getSigners()
    const deployer = accounts[0]
    const governor = accounts[0]
    const treasury = accounts[1]
    const oracles = accounts.slice(2, 5)
    const rewardsMinOracles = 2
    const validatorsMinOracles = 2

    const vaultsRegistry = await deployContract(new VaultsRegistry__factory(deployer).deploy())
    console.log('VaultsRegistry deployed at', vaultsRegistry.address)

    const validatorsRegistry = await deployContract(
      (
        await ethers.getContractFactory(
          ethValidatorsRegistry.abi,
          ethValidatorsRegistry.bytecode,
          deployer
        )
      ).deploy()
    )
    console.log('ValidatorsRegistry deployed at', validatorsRegistry.address)

    const sharedMevEscrow = await deployContract(
      new SharedMevEscrow__factory(deployer).deploy(vaultsRegistry.address)
    )
    console.log('SharedMevEscrow deployed at', sharedMevEscrow.address)

    const keeperCalculatedAddress = getContractAddress({
      from: deployer.address,
      nonce: (await deployer.getTransactionCount()) + 1,
    })
    const osToken = await deployContract(
      new OsToken__factory(deployer).deploy(
        keeperCalculatedAddress,
        vaultsRegistry.address,
        treasury.address,
        goerliConfig.osTokenFeePercent,
        goerliConfig.osTokenCapacity,
        goerliConfig.osTokenName,
        goerliConfig.osTokenSymbol
      )
    )
    console.log('OsToken deployed at', osToken.address)

    const keeper = await deployContract(
      new Keeper__factory(deployer).deploy(
        sharedMevEscrow.address,
        vaultsRegistry.address,
        osToken.address,
        goerliConfig.rewardsDelay,
        goerliConfig.maxAvgRewardPerSecond,
        validatorsRegistry.address
      )
    )
    if (keeper.address !== keeperCalculatedAddress) {
      throw new Error('Keeper address mismatch')
    }
    console.log('Keeper deployed at', keeper.address)

    for (let i = 0; i < oracles.length; i++) {
      await keeper.addOracle(oracles[i].address)
      console.log('Oracle added', oracles[i].address)
    }
    await keeper.setRewardsMinOracles(rewardsMinOracles)
    console.log('RewardsMinOracles set to', rewardsMinOracles)
    await keeper.setValidatorsMinOracles(validatorsMinOracles)
    console.log('ValidatorsMinOracles set to', validatorsMinOracles)

    const osTokenConfig = await deployContract(
      new OsTokenConfig__factory(deployer).deploy(governor.address, {
        redeemFromLtvPercent: goerliConfig.redeemFromLtvPercent,
        redeemToLtvPercent: goerliConfig.redeemToLtvPercent,
        liqThresholdPercent: goerliConfig.liqThresholdPercent,
        liqBonusPercent: goerliConfig.liqBonusPercent,
        ltvPercent: goerliConfig.ltvPercent,
      })
    )
    console.log('OsTokenConfig deployed at', osTokenConfig.address)

    const factories: string[] = []
    for (const vaultType of ['EthVault', 'EthPrivVault', 'EthErc20Vault', 'EthPrivErc20Vault']) {
      const vault = await ethers.getContractFactory(vaultType)
      const vaultImpl = (await upgrades.deployImplementation(vault, {
        unsafeAllow: ['delegatecall'],
        constructorArgs: [
          keeper.address,
          vaultsRegistry.address,
          validatorsRegistry.address,
          osToken.address,
          osTokenConfig.address,
          sharedMevEscrow.address,
        ],
      })) as string
      console.log(`${vaultType} implementation deployed at`, vaultImpl)

      const ethVaultFactory = await deployContract(
        new EthVaultFactory__factory(deployer).deploy(vaultImpl, vaultsRegistry.address)
      )
      console.log(`${vaultType}Factory deployed at`, ethVaultFactory.address)

      await vaultsRegistry.addFactory(ethVaultFactory.address)
      console.log(`Added ${vaultType}Factory to VaultsRegistry`)

      await osToken.setVaultImplementation(vaultImpl, true)
      console.log(`Added ${vaultType} implementation to OsToken`)
      factories.push(ethVaultFactory.address)
    }

    const priceFeed = await deployContract(
      new PriceFeed__factory(deployer).deploy(osToken.address, goerliConfig.priceFeedDescription)
    )
    console.log('PriceFeed deployed at', priceFeed.address)

    // pass ownership to governor
    await vaultsRegistry.transferOwnership(governor.address)
    await keeper.transferOwnership(governor.address)
    await osToken.transferOwnership(governor.address)
    console.log('Ownership transferred to governor')

    // accept ownership from governor
    await keeper.connect(governor).acceptOwnership()
    await osToken.connect(governor).acceptOwnership()
    await vaultsRegistry.connect(governor).acceptOwnership()
    console.log('Ownership accepted from governor')

    // Save the addresses
    const addresses = {
      VaultsRegistry: vaultsRegistry.address,
      Keeper: keeper.address,
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

    console.log(
      'NB! GenesisEthVault is not deployed as ' +
        'it requires StakeWise V2 StakedEthToken and PoolEscrow contracts'
    )
  }
)
