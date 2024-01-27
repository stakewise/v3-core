import { ByteVectorType, ContainerType, Type, UintNumberType } from '@chainsafe/ssz'
import { StandardMerkleTree } from '@openzeppelin/merkle-tree'
import { ethers, network } from 'hardhat'
import { Buffer } from 'buffer'
import { BytesLike, Contract, ContractTransactionResponse, Signer } from 'ethers'
import bls from 'bls-eth-wasm'
import { EthVault, Keeper, EthFoxVault } from '../../typechain-types'
import {
  EIP712Domain,
  KeeperUpdateExitSignaturesSig,
  KeeperValidatorsSig,
  VALIDATORS_DEADLINE,
  VALIDATORS_MIN_ORACLES,
} from './constants'
import { getOraclesSignatures } from './fixtures'

export const secretKeys = [
  '0x2c66340f2d886f3fc4cfef10a802ddbaf4a37ffb49533b604f8a50804e8d198f',
  '0x2c414222bc55f3a3627e20f2eb879b4019ffc44498ffbfb277725186954b714d',
  '0x51017d92e2691f20907a62a2ec91764be253b317d2f7fba42a8ac7f0290880de',
  '0x62ff87f6e66e9f2d8b382bd91fce8f31e46cceb32a84fb2d1ee1859b46399df7',
  '0x161830b452d394152b53a2b04cea5ff3312e0165628081404542c127220deea7',
  '0x64821642c5654f620bdbe72c641a3c3607aadaeb0af14311ff3588228135cc6e',
  '0x3ee3c3001ff2a6eb2830dc44031dad1a1af8906fd8e1c4a6073cbb42deadeebd',
  '0x4bbeb944e4abb46d929e6c2b7c6fea0adbdb72f942f8fa825bfb375e175e2762',
  '0x047a48f9d1790ebe3f9cde4e93f1e135beef0406f68d6c8dae42b0adef2ad8d2',
  '0x0d5b3814d2242c03bef667daf6823c866e9f458617667043a30fe5f5f3996f4b',
]

export const exitSignatureIpfsHashes = [
  'QmUFSdZoQUqkRkAgDEtFa2fMmWhQLC7tx8J3ckCL7XkZ1T',
  'QmUE7ixjUY9A3hK13HWDNztJ6SyPDutUEmFBSjj5XJfGa8',
  'QmWeQTjiM5UZrNtqiBe5VynNitHADSoCny8z1i4aMGTi6C',
  'QmbkxyF2xNibmwMds3dmvqAMn6RK7UbWwG4Y8Lz5meZUu5',
  'QmS7TDL3ATbiQySsVTasJ4Luw3WMHgYBaGw2eBJb9t9t2A',
  'QmRWw7QHKy72pKrJkukG5xxPqEr9XHktyhCmyf33wMUZzS',
  'QmbBRfY6xgBsHU2f3YitqB5ay1xJaAPEekcG1tW51tD3wD',
  'QmSPpB4TEEW8JjfuzhzFqsPnkMSVyfwMxqHhoGC5hTQL8s',
  'Qmccn5jxLqDMdY3c5nibVUtRtx3Vt7sGfMxCUD2jUSmBa1',
  'QmemVbNEhXugNCG3sjWHFS6wSH74wBvKBfiW86H1dBnwfV',
]

const DOMAIN_DEPOSIT = Uint8Array.from([3, 0, 0, 0])
const ETH1_ADDRESS_WITHDRAWAL_PREFIX = Uint8Array.from([1])
const GENESIS_FORK_VERSION = ethers.getBytes('0x00000000')
const ZERO_HASH = Buffer.alloc(32, 0)

// SSZ types
const Bytes4 = new ByteVectorType(4)
const Bytes32 = new ByteVectorType(32)
const Bytes48 = new ByteVectorType(48)
const Bytes96 = new ByteVectorType(96)
const UintNum64 = new UintNumberType(8)

const SigningData = new ContainerType(
  {
    objectRoot: Bytes32,
    domain: Bytes32,
  },
  { typeName: 'SigningData', jsonCase: 'eth2' }
)
const ForkData = new ContainerType(
  {
    currentVersion: Bytes4,
    genesisValidatorsRoot: Bytes32,
  },
  { typeName: 'ForkData', jsonCase: 'eth2' }
)

const DepositMessage = new ContainerType(
  {
    pubkey: Bytes48,
    withdrawalCredentials: Bytes32,
    amount: UintNum64,
  },
  { typeName: 'DepositMessage', jsonCase: 'eth2' }
)
const DepositData = new ContainerType(
  {
    pubkey: Bytes48,
    withdrawalCredentials: Bytes32,
    amount: UintNum64,
    signature: Bytes96,
  },
  { typeName: 'DepositData', jsonCase: 'eth2' }
)

export type ValidatorsMultiProof = {
  proofFlags: boolean[]
  proof: string[]
  leaves: [Buffer, number][]
}

export type ValidatorsTree = StandardMerkleTree<[Buffer, number]>

export type EthValidatorsData = {
  root: string
  tree: ValidatorsTree
  validators: Buffer[]
}

// Only used by processDeposit +  lightclient
/**
 * Return the domain for the [[domainType]] and [[forkVersion]].
 */
function computeDomain(domainType, forkVersion, genesisValidatorRoot): Uint8Array {
  const forkDataRoot = computeForkDataRoot(forkVersion, genesisValidatorRoot)
  const domain = new Uint8Array(32)
  domain.set(domainType, 0)
  domain.set(forkDataRoot.slice(0, 28), 4)
  return domain
}

/**
 * Used primarily in signature domains to avoid collisions across forks/chains.
 */
function computeForkDataRoot(currentVersion, genesisValidatorsRoot): Uint8Array {
  const forkData = {
    currentVersion,
    genesisValidatorsRoot,
  }
  return ForkData.hashTreeRoot(forkData)
}

/**
 * Return the signing root of an object by calculating the root of the object-domain tree.
 */
function computeSigningRoot<T>(type: Type<T>, sszObject: T, domain): Uint8Array {
  const domainWrappedObject = {
    objectRoot: type.hashTreeRoot(sszObject),
    domain,
  }
  return SigningData.hashTreeRoot(domainWrappedObject)
}

export function getWithdrawalCredentials(vaultAddress: string): Buffer {
  return Buffer.concat([
    ETH1_ADDRESS_WITHDRAWAL_PREFIX,
    Buffer.alloc(11),
    ethers.getBytes(vaultAddress),
  ])
}

export async function createValidators(
  depositAmount: bigint,
  vaultAddress: string
): Promise<Buffer[]> {
  await bls.init(bls.BLS12_381)

  const withdrawalCredentials = getWithdrawalCredentials(vaultAddress)
  const validators: Buffer[] = []
  for (let i = 0; i < secretKeys.length; i++) {
    const secretKey = new bls.SecretKey()
    secretKey.deserialize(ethers.getBytes(secretKeys[i]))
    const publicKey = secretKey.getPublicKey().serialize()

    // create DepositData
    const depositData = {
      pubkey: publicKey,
      withdrawalCredentials,
      amount: Number(depositAmount / 1000000000n), // convert to gwei
      signature: Buffer.alloc(0),
    }
    const domain = computeDomain(DOMAIN_DEPOSIT, GENESIS_FORK_VERSION, ZERO_HASH)
    const signingRoot = computeSigningRoot(DepositMessage, depositData, domain)
    const signature = secretKey.sign(signingRoot).serialize()
    depositData.signature = Buffer.from(signature)
    validators.push(Buffer.concat([publicKey, signature, DepositData.hashTreeRoot(depositData)]))
  }
  return validators
}

export function appendDepositData(
  validator: Buffer,
  depositAmount: bigint,
  vaultAddress: string
): Buffer {
  const withdrawalCredentials = getWithdrawalCredentials(vaultAddress)

  // create DepositData
  const depositData = {
    pubkey: validator.subarray(0, 48),
    withdrawalCredentials,
    amount: Number(depositAmount / 1000000000n), // convert to gwei
    signature: validator.subarray(48, 144),
  }
  return Buffer.concat([validator, DepositData.hashTreeRoot(depositData)])
}

export async function createEthValidatorsData(
  vault: EthVault | EthFoxVault
): Promise<EthValidatorsData> {
  const validatorDeposit = ethers.parseEther('32')
  const validators = await createValidators(validatorDeposit, await vault.getAddress())
  const tree = StandardMerkleTree.of(
    validators.map((v, i) => [v, i]),
    ['bytes', 'uint256']
  ) as ValidatorsTree
  const treeRoot = tree.root

  return {
    root: treeRoot,
    tree,
    validators,
  }
}

export async function getEthValidatorsSigningData(
  validators: Buffer,
  deadline: bigint,
  exitSignaturesIpfsHash: string,
  keeper: Keeper,
  vault: EthVault | EthFoxVault,
  validatorsRegistryRoot: BytesLike
) {
  return {
    primaryType: 'KeeperValidators',
    types: { EIP712Domain, KeeperValidators: KeeperValidatorsSig },
    domain: {
      name: 'KeeperOracles',
      version: '1',
      chainId: network.config.chainId,
      verifyingContract: await keeper.getAddress(),
    },
    message: {
      validatorsRegistryRoot,
      vault: await vault.getAddress(),
      validators,
      exitSignaturesIpfsHash,
      deadline,
    },
  }
}

export async function getEthValidatorsExitSignaturesSigningData(
  keeper: Keeper,
  vault: EthVault,
  deadline: number,
  exitSignaturesIpfsHash: string,
  nonce: number
) {
  return {
    primaryType: 'KeeperValidators',
    types: { EIP712Domain, KeeperValidators: KeeperUpdateExitSignaturesSig },
    domain: {
      name: 'KeeperOracles',
      version: '1',
      chainId: network.config.chainId,
      verifyingContract: await keeper.getAddress(),
    },
    message: {
      vault: await vault.getAddress(),
      deadline,
      nonce,
      exitSignaturesIpfsHash,
    },
  }
}

export function getValidatorProof(
  tree: ValidatorsTree,
  validator: Buffer,
  index: number
): string[] {
  return tree.getProof([validator, index])
}

export function getValidatorsMultiProof(
  tree: ValidatorsTree,
  validators: Buffer[],
  indexes: number[]
): ValidatorsMultiProof {
  const multiProof = tree.getMultiProof(validators.map((v, i) => [v, indexes[i]]))
  return {
    ...multiProof,
    leaves: multiProof.leaves,
  }
}

export async function registerEthValidator(
  vault: EthVault | EthFoxVault,
  keeper: Keeper,
  validatorsRegistry: Contract,
  admin: Signer
): Promise<ContractTransactionResponse> {
  const validatorsData = await createEthValidatorsData(vault)
  const validatorsRegistryRoot = await validatorsRegistry.get_deposit_root()
  await vault.connect(admin).setValidatorsRoot(validatorsData.root)
  const validator = validatorsData.validators[0]
  const exitSignatureIpfsHash = exitSignatureIpfsHashes[0]
  const signingData = await getEthValidatorsSigningData(
    validator,
    VALIDATORS_DEADLINE,
    exitSignatureIpfsHash,
    keeper,
    vault,
    validatorsRegistryRoot
  )
  const signatures = getOraclesSignatures(signingData, VALIDATORS_MIN_ORACLES)
  const proof = getValidatorProof(validatorsData.tree, validator, 0)
  return await vault.registerValidator(
    {
      validatorsRegistryRoot,
      validators: validator,
      signatures,
      exitSignaturesIpfsHash: exitSignatureIpfsHash,
      deadline: VALIDATORS_DEADLINE,
    },
    proof
  )
}
