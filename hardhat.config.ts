import { HardhatUserConfig } from 'hardhat/types'
import dotenv from 'dotenv'
import glob from 'glob'
import path from 'path'
import '@nomicfoundation/hardhat-toolbox'
import 'hardhat-contract-sizer'
import 'hardhat-log-remover'
import 'hardhat-spdx-license-identifier'
import 'hardhat-abi-exporter'
import '@openzeppelin/hardhat-upgrades'

dotenv.config({ path: '.env' })

import { Networks } from './helpers/types'
import { NETWORKS } from './helpers/constants'

if (!process.env.SKIP_LOAD) {
  glob.sync('./tasks/*.ts').forEach((file) => {
    require(path.resolve(file))
  })
}

const DEFAULT_BLOCK_GAS_LIMIT = 12450000
const MNEMONIC_PATH = "m/44'/60'/0'/0"
const MNEMONIC = process.env.MNEMONIC || ''
const TRACK_GAS = process.env.TRACK_GAS === 'true'
const IS_COVERAGE = process.env.COVERAGE === 'true'
const BLOCK_EXPLORER_KEY = process.env.BLOCK_EXPLORER_KEY || ''
const HARDHATEVM_CHAINID = 31337

const getCommonNetworkConfig = (networkName) => {
  return {
    url: NETWORKS[networkName].url,
    chainId: NETWORKS[networkName].chainId,
    accounts: {
      mnemonic: MNEMONIC,
      path: MNEMONIC_PATH,
      initialIndex: 0,
      count: 20,
    },
  }
}

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: '0.8.20',
        settings: {
          viaIR: !IS_COVERAGE,
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
    goerli: getCommonNetworkConfig(Networks.goerli),
    holesky: getCommonNetworkConfig(Networks.holesky),
    mainnet: getCommonNetworkConfig(Networks.mainnet),
    hardhat: {
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
    local: {
      url: 'http://127.0.0.1:8545/',
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
    only: ['interfaces/', 'libraries/'],
    spacing: 2,
  },
  etherscan: {
    apiKey: BLOCK_EXPLORER_KEY,
    customChains: [
      {
        network: 'holesky',
        chainId: 17000,
        urls: {
          apiURL: 'https://api-holesky.etherscan.io/api',
          browserURL: 'https://holesky.etherscan.io',
        },
      },
    ],
  },
}

export default config
