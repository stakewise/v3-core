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

  await verify(
    hre,
    vaultsRegistry.address,
    [networkConfig.governor],
    'contracts/vaults/VaultsRegistry.sol:VaultsRegistry'
  )

  const oracles = await deployContract(
    new Oracles__factory(deployer).deploy(
      networkConfig.governor,
      networkConfig.oracles,
      networkConfig.requiredOracles,
      networkConfig.oraclesConfigIpfsHash
    )
  )
  console.log('Oracles deployed at', oracles.address)

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
    nonce: (await deployer.getTransactionCount()) + 2,
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

  await verify(
    hre,
    osToken.address,
    [
      '0x996461A815191bDE7FAdb7ABAbA9053cd6969CAA',
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

  const keeper = await upgrades.deployProxy(
    new Keeper__factory(deployer),
    [networkConfig.governor, networkConfig.rewardsDelay],
    {
      unsafeAllow: ['delegatecall'],
      constructorArgs: [
        sharedMevEscrow.address,
        oracles.address,
        vaultsRegistry.address,
        osToken.address,
        networkConfig.validatorsRegistry,
      ],
    }
  )
  await keeper.deployed()
  if (keeper.address !== keeperCalculatedAddress) {
    throw new Error('Keeper address mismatch')
  }
  console.log('Keeper deployed at', keeper.address)

  await verify(
    hre,
    await new Keeper__factory(deployer).attach(keeper.address).implementation(),
    [
      sharedMevEscrow.address,
      oracles.address,
      vaultsRegistry.address,
      osToken.address,
      networkConfig.validatorsRegistry,
    ],
    'contracts/keeper/Keeper.sol:Keeper'
  )

  const osTokenConfig = await deployContract(
    new OsTokenConfig__factory(deployer).deploy(
      networkConfig.governor,
      networkConfig.osTokenRedeemStartHf,
      networkConfig.osTokenRedeemMaxHf,
      networkConfig.osTokenLiqThreshold,
      networkConfig.osTokenLiqBonus,
      networkConfig.osTokenLtv
    )
  )
  console.log('OsTokenConfig deployed at', osTokenConfig.address)

  await verify(
    hre,
    osTokenConfig.address,
    [
      networkConfig.governor,
      networkConfig.osTokenRedeemStartHf,
      networkConfig.osTokenRedeemMaxHf,
      networkConfig.osTokenLiqThreshold,
      networkConfig.osTokenLiqBonus,
      networkConfig.osTokenLtv,
    ],
    'contracts/osToken/OsTokenConfig.sol:OsTokenConfig'
  )

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
