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
} from '../typechain-types'
import { deployContract } from '../helpers/utils'
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
    const vaultsRegistryAddress = await vaultsRegistry.getAddress()
    console.log('VaultsRegistry deployed at', vaultsRegistryAddress)

    const validatorsRegistry = await deployContract(
      (
        await ethers.getContractFactory(
          ethValidatorsRegistry.abi,
          ethValidatorsRegistry.bytecode,
          deployer
        )
      ).deploy()
    )
    const validatorsRegistryAddress = await validatorsRegistry.getAddress()
    console.log('ValidatorsRegistry deployed at', validatorsRegistryAddress)

    const sharedMevEscrow = await deployContract(
      new SharedMevEscrow__factory(deployer).deploy(vaultsRegistryAddress)
    )
    const sharedMevEscrowAddress = await sharedMevEscrow.getAddress()
    console.log('SharedMevEscrow deployed at', sharedMevEscrowAddress)

    const keeperCalculatedAddress = ethers.getCreateAddress({
      from: deployer.address,
      nonce: (await ethers.provider.getTransactionCount(deployer.address)) + 1,
    })
    const osToken = await deployContract(
      new OsToken__factory(deployer).deploy(
        keeperCalculatedAddress,
        vaultsRegistryAddress,
        treasury.address,
        goerliConfig.osTokenFeePercent,
        goerliConfig.osTokenCapacity,
        goerliConfig.osTokenName,
        goerliConfig.osTokenSymbol
      )
    )
    const osTokenAddress = await osToken.getAddress()
    console.log('OsToken deployed at', osTokenAddress)

    const keeper = await deployContract(
      new Keeper__factory(deployer).deploy(
        sharedMevEscrowAddress,
        vaultsRegistryAddress,
        osTokenAddress,
        goerliConfig.rewardsDelay,
        goerliConfig.maxAvgRewardPerSecond,
        validatorsRegistryAddress
      )
    )
    const keeperAddress = await keeper.getAddress()
    if (keeperAddress !== keeperCalculatedAddress) {
      throw new Error('Keeper address mismatch')
    }
    console.log('Keeper deployed at', keeperAddress)

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
          keeperAddress,
          vaultsRegistryAddress,
          validatorsRegistryAddress,
          osTokenAddress,
          osTokenConfig.address,
          sharedMevEscrowAddress,
        ],
      })) as string
      console.log(`${vaultType} implementation deployed at`, vaultImpl)

      const ethVaultFactory = await deployContract(
        new EthVaultFactory__factory(deployer).deploy(vaultImpl, vaultsRegistryAddress)
      )
      const ethVaultFactoryAddress = await ethVaultFactory.getAddress()
      console.log(`${vaultType}Factory deployed at`, ethVaultFactoryAddress)

      await vaultsRegistry.addFactory(ethVaultFactoryAddress)
      console.log(`Added ${vaultType}Factory to VaultsRegistry`)

      await osToken.setVaultImplementation(vaultImpl, true)
      console.log(`Added ${vaultType} implementation to OsToken`)
      factories.push(ethVaultFactoryAddress)
    }

    const priceFeed = await deployContract(
      new PriceFeed__factory(deployer).deploy(osTokenAddress, goerliConfig.priceFeedDescription)
    )
    console.log('PriceFeed deployed at', priceFeed.address)

    const rewardSplitterImpl = await deployContract(new RewardSplitter__factory(deployer).deploy())
    const rewardSplitterImplAddress = await rewardSplitterImpl.getAddress()
    console.log('RewardSplitter implementation deployed at', rewardSplitterImplAddress)

    const rewardSplitterFactory = await deployContract(
      new RewardSplitterFactory__factory(deployer).deploy(rewardSplitterImplAddress)
    )
    console.log('RewardSplitterFactory deployed at', rewardSplitterFactory.address)

    const cumulativeMerkleDrop = await deployContract(
      new CumulativeMerkleDrop__factory(deployer).deploy(
        goerliConfig.liquidityCommittee,
        goerliConfig.swiseToken
      )
    )
    console.log('CumulativeMerkleDrop deployed at', cumulativeMerkleDrop.address)

    // pass ownership to governor
    await vaultsRegistry.transferOwnership(governor.address)
    await keeper.transferOwnership(governor.address)
    await osToken.transferOwnership(governor.address)
    console.log('Ownership transferred to governor')

    // accept ownership from governor
    await Keeper__factory.connect(keeperAddress, governor).acceptOwnership()
    await OsToken__factory.connect(osTokenAddress, governor).acceptOwnership()
    await VaultsRegistry__factory.connect(vaultsRegistryAddress, governor).acceptOwnership()
    console.log('Ownership accepted from governor')

    // Save the addresses
    const addresses = {
      VaultsRegistry: vaultsRegistryAddress,
      Keeper: keeperAddress,
      EthVaultFactory: factories[0],
      EthPrivVaultFactory: factories[1],
      EthErc20VaultFactory: factories[2],
      EthPrivErc20VaultFactory: factories[3],
      SharedMevEscrow: sharedMevEscrowAddress,
      OsToken: osTokenAddress,
      OsTokenConfig: osTokenConfig.address,
      PriceFeed: priceFeed.address,
      RewardSplitterFactory: rewardSplitterFactory.address,
    }
    const json = JSON.stringify(addresses, null, 2)
    const fileName = `${DEPLOYMENTS_DIR}/${networkName}.json`

    if (!fs.existsSync(DEPLOYMENTS_DIR)) {
      fs.mkdirSync(DEPLOYMENTS_DIR)
    }

    fs.writeFileSync(fileName, json, 'utf-8')
    console.log('Saved to', fileName)

    console.log(
      'NB! EthGenesisVault is not deployed as ' +
        'it requires StakeWise V2 StakedEthToken and PoolEscrow contracts'
    )
  }
)
