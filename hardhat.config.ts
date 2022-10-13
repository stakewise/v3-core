import { HardhatUserConfig } from 'hardhat/types'
import dotenv from 'dotenv'
import glob from 'glob'
import path from 'path'
import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-etherscan'
import '@nomiclabs/hardhat-waffle'
import '@typechain/hardhat'
import 'solidity-coverage'
import 'hardhat-gas-reporter'
import 'hardhat-contract-sizer'
import 'hardhat-log-remover'
import 'hardhat-spdx-license-identifier'
import 'hardhat-abi-exporter'
import '@openzeppelin/hardhat-upgrades'
import { EthereumNetwork } from './helpers/types'

dotenv.config({ path: '.env' })

if (!process.env.SKIP_LOAD) {
  glob.sync('./tasks/*.ts').forEach((file) => {
    require(path.resolve(file))
  })
}

const DEFAULT_BLOCK_GAS_LIMIT = 12450000
const MNEMONIC_PATH = "m/44'/60'/0'/0"
const MNEMONIC = process.env.MNEMONIC || ''
const TRACK_GAS = process.env.TRACK_GAS === 'true'
const BLOCK_EXPLORER_KEY = process.env.BLOCK_EXPLORER_KEY || ''
const HARDHATEVM_CHAINID = 31337

const networkConfig = {
  [EthereumNetwork.goerli]: {
    url: process.env.GOERLI_RPC_URL || '',
    chainId: 5,
  },
}

const getCommonNetworkConfig = (networkName) => ({
  url: networkConfig[networkName].url,
  chainId: networkConfig[networkName].chainId,
  accounts: {
    mnemonic: MNEMONIC,
    path: MNEMONIC_PATH,
    initialIndex: 0,
    count: 20,
  },
})

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: '0.8.17',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
            details: {
              yul: true,
            },
          },
        },
      },
    ],
  },
  networks: {
    goerli: getCommonNetworkConfig(EthereumNetwork.goerli),
    hardhat: {
      hardfork: 'merge',
      blockGasLimit: DEFAULT_BLOCK_GAS_LIMIT,
      gas: DEFAULT_BLOCK_GAS_LIMIT,
      gasPrice: 8000000000,
      chainId: HARDHATEVM_CHAINID,
      throwOnTransactionFailures: true,
      throwOnCallFailures: true,
      accounts: {
        accountsBalance: '1000000000000000000000000',
      },
    },
  },
  mocha: {
    timeout: 100000000,
  },
  gasReporter: {
    enabled: TRACK_GAS,
  },
  spdxLicenseIdentifier: {
    overwrite: false,
    runOnCompile: false,
  },
  abiExporter: {
    path: './abi',
    clear: true,
    flat: true,
    only: ['interfaces/'],
    spacing: 2,
  },
  etherscan: {
    apiKey: BLOCK_EXPLORER_KEY,
  },
}

export default config
