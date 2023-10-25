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
  OsTokenVaultController__factory,
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

    const osTokenAddress = ethers.getCreateAddress({
      from: deployer.address,
      nonce: (await ethers.provider.getTransactionCount(deployer.address)) + 1,
    })

    const keeperAddress = ethers.getCreateAddress({
      from: deployer.address,
      nonce: (await ethers.provider.getTransactionCount(deployer.address)) + 2,
    })
    const osTokenVaultController = await deployContract(
      new OsTokenVaultController__factory(deployer).deploy(
        keeperAddress,
        vaultsRegistryAddress,
        osTokenAddress,
        treasury.address,
        governor.address,
        goerliConfig.osTokenFeePercent,
        goerliConfig.osTokenCapacity
      )
    )
    const osTokenVaultControllerAddress = await osTokenVaultController.getAddress()
    console.log('OsTokenVaultController deployed at', osTokenVaultControllerAddress)

    const osToken = await deployContract(
      new OsToken__factory(deployer).deploy(
        governor.address,
        osTokenVaultControllerAddress,
        goerliConfig.osTokenName,
        goerliConfig.osTokenSymbol
      )
    )
    if ((await osToken.getAddress()) !== osTokenAddress) {
      throw new Error('OsToken address mismatch')
    }
    console.log('OsToken deployed at', osTokenAddress)

    const keeper = await deployContract(
      new Keeper__factory(deployer).deploy(
        sharedMevEscrowAddress,
        vaultsRegistryAddress,
        osTokenVaultControllerAddress,
        goerliConfig.rewardsDelay,
        goerliConfig.maxAvgRewardPerSecond,
        goerliConfig.validatorsRegistry
      )
    )
    if ((await keeper.getAddress()) !== keeperAddress) {
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
    const osTokenConfigAddress = await osTokenConfig.getAddress()
    console.log('OsTokenConfig deployed at', osTokenConfigAddress)

    const factories: string[] = []
    for (const vaultType of ['EthVault', 'EthPrivVault', 'EthErc20Vault', 'EthPrivErc20Vault']) {
      const vault = await ethers.getContractFactory(vaultType)
      const vaultImpl = (await upgrades.deployImplementation(vault, {
        unsafeAllow: ['delegatecall'],
        constructorArgs: [
          keeperAddress,
          vaultsRegistryAddress,
          validatorsRegistryAddress,
          osTokenVaultControllerAddress,
          osTokenConfigAddress,
          sharedMevEscrowAddress,
          goerliConfig.exitedAssetsClaimDelay,
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

      await vaultsRegistry.addVaultImpl(vaultImpl)
      console.log(`Added ${vaultType} implementation to VaultsRegistry`)
      factories.push(ethVaultFactoryAddress)
    }

    const priceFeed = await deployContract(
      new PriceFeed__factory(deployer).deploy(
        osTokenVaultControllerAddress,
        goerliConfig.priceFeedDescription
      )
    )
    const priceFeedAddress = await priceFeed.getAddress()
    console.log('PriceFeed deployed at', priceFeedAddress)

    const rewardSplitterImpl = await deployContract(new RewardSplitter__factory(deployer).deploy())
    const rewardSplitterImplAddress = await rewardSplitterImpl.getAddress()
    console.log('RewardSplitter implementation deployed at', rewardSplitterImplAddress)

    const rewardSplitterFactory = await deployContract(
      new RewardSplitterFactory__factory(deployer).deploy(rewardSplitterImplAddress)
    )
    const rewardSplitterFactoryAddress = await rewardSplitterFactory.getAddress()
    console.log('RewardSplitterFactory deployed at', rewardSplitterFactoryAddress)

    const cumulativeMerkleDrop = await deployContract(
      new CumulativeMerkleDrop__factory(deployer).deploy(
        goerliConfig.liquidityCommittee,
        goerliConfig.swiseToken
      )
    )
    const cumulativeMerkleDropAddress = await cumulativeMerkleDrop.getAddress()
    console.log('CumulativeMerkleDrop deployed at', cumulativeMerkleDropAddress)

    // pass ownership to governor
    await vaultsRegistry.transferOwnership(governor.address)
    await keeper.transferOwnership(governor.address)
    await osToken.transferOwnership(governor.address)
    console.log('Ownership transferred to governor')

    // transfer ownership to governor
    await vaultsRegistry.initialize(governor.address)
    console.log('VaultsRegistry ownership transferred to', governor.address)

    await keeper.initialize(governor.address)
    console.log('Keeper ownership transferred to', governor.address)

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
      OsTokenConfig: osTokenConfigAddress,
      osTokenVaultController: osTokenVaultControllerAddress,
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

    console.log(
      'NB! EthGenesisVault is not deployed as ' +
        'it requires StakeWise V2 StakedEthToken and PoolEscrow contracts'
    )
  }
)
