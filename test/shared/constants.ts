import { ethers } from 'ethers'

export const PANIC_CODES = {
  ARITHMETIC_UNDER_OR_OVERFLOW: 0x11,
  DIVISION_BY_ZERO: 0x12,
  OUT_OF_BOUND_INDEX: 0x32,
}

export const SECURITY_DEPOSIT = 1000000000n
export const MAX_UINT256 = 2n ** 256n - 1n
export const MAX_UINT16 = 2n ** 16n - 1n
export const MAX_UINT128 = 2n ** 128n - 1n
export const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'
export const ZERO_BYTES32 = '0x0000000000000000000000000000000000000000000000000000000000000000'
export const ONE_DAY = 86400

export const VALIDATORS_DEADLINE = 1914150396n

export const REWARDS_DELAY = ONE_DAY / 2 // 12 hours
export const ORACLES = [
  Buffer.from('c2bc8560ffcc278ded2efffaccfc4ce08b2a3a867eb744cec45732603e30ebf7', 'hex'),
  Buffer.from('aff434fa2127355afdf265af1ba7e1d1384ffca4b7c2a8b7b9e04d23e316f395', 'hex'),
  Buffer.from('cdb517b473daa98584897f3d224453ec4b1ed574ad98697a0e910103599903d6', 'hex'),
  Buffer.from('f6e9186ab80c4e210edf231708353727cfd65a0211fa483e144cd5bf72913a3b', 'hex'),
  Buffer.from('d44d4b9d464979a765d668ed9c83150048b6cb6be363ebec5b4e929d1513f126', 'hex'),
  Buffer.from('1d523e07453be2a5ad304e7fb950713a6021bbcbe5bd8c19b15033a419abea67', 'hex'),
  Buffer.from('6b64cbac8e5a12f78bd984b99df2c1a1984665017068531ccf9fe7b35bacb518', 'hex'),
  Buffer.from('16594b5022a199029ae2614b1906c03ffc8b0fc1f2a1efb5836275a1e52f611a', 'hex'),
  Buffer.from('27bad568920a145813ff66b73360c84f221043e1861fcfdf43f9d150e84202ea', 'hex'),
  Buffer.from('06087f518d2c684d1a2a3523fe358f3fdc45dfe560cf7a7ccb8ba01da7786796', 'hex'),
  Buffer.from('3999c56744678c5cb451df5eadf2846b92aa158b6d5eda55775f27064c6e880a', 'hex'),
  Buffer.from('ca960119ad719a55764d0f5913fb354c301f614d3f49219c7b03202b2062890f', 'hex'),
]
export const REWARDS_MIN_ORACLES = 6
export const VALIDATORS_MIN_ORACLES = 6
export const ORACLES_CONFIG = 'QmbwQ6zFEWs1SjLPGk4NNJqn4wduVe6dK3xyte2iG59Uru'
export const EXITING_ASSETS_MIN_DELAY = 24 * 60 * 60 // 24 hours
export const OSTOKEN_FEE = 500 // 5%
export const OSTOKEN_CAPACITY = ethers.parseEther('10000000')
export const OSTOKEN_NAME = 'Staked ETH'
export const OSTOKEN_SYMBOL = 'osETH'

export const OSTOKEN_LIQ_THRESHOLD = 9200 // 92%
export const OSTOKEN_LIQ_BONUS = 10100 // 101%
export const OSTOKEN_LTV = 9000 // 90%

export const OSTOKEN_REDEEM_FROM_LTV = 9150 // 91.5%
export const OSTOKEN_REDEEM_TO_LTV = 9000 // 90%
export const MAX_AVG_REWARD_PER_SECOND = 6341958397 // 20% APY

export const XDAI_EXCHANGE_MAX_SLIPPAGE = 50 // 0.5%

export const XDAI_EXCHANGE_STALE_PRICE_TIME_DELTA = 86400 // 1 day

export const EIP712Domain = [
  { name: 'name', type: 'string' },
  { name: 'version', type: 'string' },
  { name: 'chainId', type: 'uint256' },
  { name: 'verifyingContract', type: 'address' },
]

export const PermitSig = [
  { name: 'owner', type: 'address' },
  { name: 'spender', type: 'address' },
  { name: 'value', type: 'uint256' },
  { name: 'nonce', type: 'uint256' },
  { name: 'deadline', type: 'uint256' },
]

export const KeeperRewardsSig = [
  { name: 'rewardsRoot', type: 'bytes32' },
  { name: 'rewardsIpfsHash', type: 'string' },
  { name: 'avgRewardPerSecond', type: 'uint256' },
  { name: 'updateTimestamp', type: 'uint64' },
  { name: 'nonce', type: 'uint64' },
]

export const KeeperValidatorsSig = [
  { name: 'validatorsRegistryRoot', type: 'bytes32' },
  { name: 'vault', type: 'address' },
  { name: 'validators', type: 'bytes' },
  { name: 'exitSignaturesIpfsHash', type: 'string' },
  { name: 'deadline', type: 'uint256' },
]

export const KeeperUpdateExitSignaturesSig = [
  { name: 'vault', type: 'address' },
  { name: 'exitSignaturesIpfsHash', type: 'string' },
  { name: 'nonce', type: 'uint256' },
  { name: 'deadline', type: 'uint256' },
]
