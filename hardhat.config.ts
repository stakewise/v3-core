import { HardhatUserConfig } from 'hardhat/types'
import dotenv from 'dotenv'
import glob from 'glob'
import path from 'path'
import '@nomicfoundation/hardhat-toolbox'
import '@nomicfoundation/hardhat-foundry'
import 'hardhat-contract-sizer'
import 'hardhat-log-remover'
import 'hardhat-spdx-license-identifier'
import 'hardhat-abi-exporter'
import '@openzeppelin/hardhat-upgrades'

dotenv.config({ path: '.env' })

import { Networks } from './helpers/types'
import { MAINNET_FORK, NETWORKS } from './helpers/constants'

if (!process.env.SKIP_LOAD) {
  glob.sync('./tasks/*.ts').forEach((file) => {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    require(path.resolve(file))
  })
}

const DEFAULT_BLOCK_GAS_LIMIT = 12450000
const MNEMONIC_PATH = "m/44'/60'/0'/0"
const MNEMONIC = process.env.MNEMONIC || ''
const TRACK_GAS = process.env.TRACK_GAS === 'true'
const BLOCK_EXPLORER_KEY = process.env.BLOCK_EXPLORER_KEY || ''
const HARDHATEVM_CHAINID = 31337

// fork
const mainnetFork = MAINNET_FORK.rpcUrl
  ? {
      blockNumber: MAINNET_FORK.blockNumber,
      url: MAINNET_FORK.rpcUrl,
    }
  : undefined
if (mainnetFork) {
  console.log(`Using mainnet fork at block ${mainnetFork.blockNumber}`)
}

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
        version: '0.8.22',
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 200,
            details: {
              yul: true,
            },
          },
          evmVersion: 'shanghai',
        },
      },
    ],
  },
  networks: {
    hoodi: getCommonNetworkConfig(Networks.hoodi),
    mainnet: getCommonNetworkConfig(Networks.mainnet),
    chiado: getCommonNetworkConfig(Networks.chiado),
    gnosis: getCommonNetworkConfig(Networks.gnosis),
    hardhat: {
      blockGasLimit: DEFAULT_BLOCK_GAS_LIMIT,
      gas: DEFAULT_BLOCK_GAS_LIMIT,
      chainId: HARDHATEVM_CHAINID,
      throwOnTransactionFailures: true,
      throwOnCallFailures: true,
      accounts: {
        accountsBalance: '1000000000000000000000000',
      },
      forking: mainnetFork,
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
        network: 'hoodi',
        chainId: 560048,
        urls: {
          apiURL: 'https://api-hoodi.etherscan.io/api',
          browserURL: 'https://hoodi.etherscan.io',
        },
      },
    ],
  },
}

export default config
