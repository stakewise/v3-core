import { BigNumber } from 'ethers'

export const PANIC_CODES = {
  ARITHMETIC_UNDER_OR_OVERFLOW: 'panic code 0x11',
  DIVISION_BY_ZERO: 'panic code 0x12',
  OUT_OF_BOUND_INDEX: 'panic code 0x32',
}

export const SECURITY_DEPOSIT = 1000000000
export const MAX_UINT256 = BigNumber.from(2).pow(256).sub(1)
export const MAX_UINT128 = BigNumber.from(2).pow(128).sub(1)
export const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'
export const ZERO_BYTES32 = '0x0000000000000000000000000000000000000000000000000000000000000000'
export const ONE_DAY = 86400

export const REWARDS_DELAY = ONE_DAY / 2
export const ORACLES = [
  Buffer.from('09936ee85420ff724d4d002f4bb5988de94b2eae57e195b36225b9dba32f7664', 'hex'),
  Buffer.from('b11591afda00283445b9929c18ad8982955232b8e06c722d9b64ba695db64ade', 'hex'),
  Buffer.from('45b13360c7f02d323923ec2485624f230307755623629981116d2d8fb82cf949', 'hex'),
  Buffer.from('c734442412898762acf7c7f962da3d90c402b840afed440c7bc1559bd1a9ee9c', 'hex'),
  Buffer.from('a7ad4044c5ed7d39b592149b900a7283b9e5096f234d90ca80294beaaf8baa79', 'hex'),
  Buffer.from('f423949710a91e7e77dab910164345f7c3052d6804dae0b5abf364969981f8a5', 'hex'),
  Buffer.from('2b264f4651ee4be0ff9e827c78625e125f462a9f521c4fcfab4872330145b991', 'hex'),
  Buffer.from('a6b4d72b19066409389143027bb67d1a452fdcbe24a011f7012bd27d7c59787d', 'hex'),
  Buffer.from('f6223f230023a2e83f491eca4006c853c72acdf1fb0564fecaf3fef0fb8609f8', 'hex'),
  Buffer.from('b1bd9296c882de61d16495e59e8a4f56dc77c5397cf47c94912eae0a32c07f7c', 'hex'),
  Buffer.from('4f3ccc266b31bfe6545c286ff44b5d310f3406aaf2a9dd60b22baf0a8340fe0c', 'hex'),
]
export const REQUIRED_ORACLES = 6
export const ORACLES_CONFIG = 'QmbwQ6zFEWs1SjLPGk4NNJqn4wduVe6dK3xyte2iG59Uru'

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
  { name: 'rewardsIpfsHash', type: 'bytes32' },
  { name: 'updateTimestamp', type: 'uint64' },
  { name: 'nonce', type: 'uint64' },
]

export const KeeperValidatorsSig = [
  { name: 'validatorsRegistryRoot', type: 'bytes32' },
  { name: 'vault', type: 'address' },
  { name: 'validators', type: 'bytes32' },
  { name: 'exitSignaturesIpfsHash', type: 'bytes32' },
]

export const KeeperUpdateExitSignaturesSig = [
  { name: 'vault', type: 'address' },
  { name: 'exitSignaturesIpfsHash', type: 'bytes32' },
  { name: 'nonce', type: 'uint256' },
]
