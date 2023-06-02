import '@nomiclabs/hardhat-ethers'
import '@openzeppelin/hardhat-upgrades/dist/type-extensions'
import { task } from 'hardhat/config'
import { VaultsRegistry__factory } from '../typechain-types'

const FEE_DATA = {
  maxFeePerGas: '364053996066',
  maxPriorityFeePerGas: '305657672',
}

task('whitelist-factory', 'whitelists vaults factory').setAction(async (taskArgs, hre) => {
  const ethers = hre.ethers

  // Wrap the provider so we can override fee data.
  const provider = new ethers.providers.FallbackProvider([ethers.provider], 1)
  provider.getFeeData = async () => FEE_DATA

  // Create the signer for the mnemonic, connected to the provider with hardcoded fee data
  const deployer = new ethers.Wallet(process.env.ADMIN_PRIVATE_KEY, provider)

  const vaultsRegistry = new VaultsRegistry__factory(deployer).attach(
    process.env.VAULTS_REGISTRY_ADDRESS
  )
  const receipt = await vaultsRegistry.addFactory(process.env.VAULTS_FACTORY_ADDRESS)
  console.log(`Added vaults factory to registry ${receipt.hash}`)
})
