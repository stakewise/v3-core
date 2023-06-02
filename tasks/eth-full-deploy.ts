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
  SharedMevEscrow__factory,
  OsToken__factory,
  OsTokenConfig__factory,
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
      networkConfig.governor,
      networkConfig.treasury,
      networkConfig.osTokenFeePercent,
      networkConfig.osTokenCapacity,
      networkConfig.osTokenName,
      networkConfig.osTokenSymbol
    )
  )
  console.log('OsToken deployed at', osToken.address)

  const keeper = await deployContract(
    new Keeper__factory(deployer).deploy(
      sharedMevEscrow.address,
      oracles.address,
      vaultsRegistry.address,
      osToken.address,
      networkConfig.validatorsRegistry,
      networkConfig.rewardsDelay,
      networkConfig.maxAvgRewardPerSecond
    )
  )
  if (keeper.address !== keeperCalculatedAddress) {
    throw new Error('Keeper address mismatch')
  }
  console.log('Keeper deployed at', keeper.address)

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

  const publicVaultImpl = await upgrades.deployImplementation(new EthVault__factory(deployer), {
    unsafeAllow: ['delegatecall'],
    constructorArgs: [
      keeper.address,
      vaultsRegistry.address,
      networkConfig.validatorsRegistry,
      osToken.address,
      osTokenConfig.address,
      sharedMevEscrow.address,
    ],
  })

  const privateVaultImpl = await upgrades.deployImplementation(
    new EthPrivateVault__factory(deployer),
    {
      unsafeAllow: ['delegatecall'],
      constructorArgs: [
        keeper.address,
        vaultsRegistry.address,
        networkConfig.validatorsRegistry,
        osToken.address,
        osTokenConfig.address,
        sharedMevEscrow.address,
      ],
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

  await verify(
    hre,
    vaultsRegistry.address,
    [networkConfig.governor],
    'contracts/vaults/VaultsRegistry.sol:VaultsRegistry'
  )

  await verify(
    hre,
    oracles.address,
    [
      networkConfig.governor,
      networkConfig.oracles,
      networkConfig.requiredOracles,
      networkConfig.oraclesConfigIpfsHash,
    ],
    'contracts/keeper/Oracles.sol:Oracles'
  )

  await verify(
    hre,
    sharedMevEscrow.address,
    [vaultsRegistry.address],
    'contracts/vaults/ethereum/mev/SharedMevEscrow.sol:SharedMevEscrow'
  )

  await verify(
    hre,
    osToken.address,
    [
      keeperCalculatedAddress,
      vaultsRegistry.address,
      networkConfig.governor,
      networkConfig.treasury,
      networkConfig.osTokenFeePercent,
      networkConfig.osTokenCapacity,
      networkConfig.osTokenName,
      networkConfig.osTokenSymbol,
    ],
    'contracts/osToken/OsToken.sol:OsToken'
  )

  await verify(
    hre,
    keeper.address,
    [
      sharedMevEscrow.address,
      oracles.address,
      vaultsRegistry.address,
      osToken.address,
      networkConfig.validatorsRegistry,
      networkConfig.rewardsDelay,
      networkConfig.maxAvgRewardPerSecond,
    ],
    'contracts/keeper/Keeper.sol:Keeper'
  )

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

  await verify(
    hre,
    publicVaultImpl as string,
    [
      keeper.address,
      vaultsRegistry.address,
      networkConfig.validatorsRegistry,
      osToken.address,
      osTokenConfig.address,
      sharedMevEscrow.address,
    ],
    'contracts/vaults/ethereum/EthVault.sol:EthVault'
  )

  await verify(
    hre,
    privateVaultImpl as string,
    [
      keeper.address,
      vaultsRegistry.address,
      networkConfig.validatorsRegistry,
      osToken.address,
      osTokenConfig.address,
      sharedMevEscrow.address,
    ],
    'contracts/vaults/ethereum/EthPrivateVault.sol:EthPrivateVault'
  )

  await verify(
    hre,
    ethVaultFactory.address,
    [publicVaultImpl, privateVaultImpl, vaultsRegistry.address],
    'contracts/vaults/ethereum/EthVaultFactory.sol:EthVaultFactory'
  )

  // Save the addresses
  const addresses = {
    VaultsRegistry: vaultsRegistry.address,
    Oracles: oracles.address,
    Keeper: keeper.address,
    EthVaultFactory: ethVaultFactory.address,
    SharedMevEscrow: sharedMevEscrow.address,
    OsToken: osToken.address,
    OsTokenConfig: osTokenConfig.address,
  }
  const json = JSON.stringify(addresses, null, 2)
  const fileName = `${DEPLOYMENTS_DIR}/${networkName}.json`

  if (!fs.existsSync(DEPLOYMENTS_DIR)) {
    fs.mkdirSync(DEPLOYMENTS_DIR)
  }

  fs.writeFileSync(fileName, json, 'utf-8')
  console.log('Saved to', fileName)
})
