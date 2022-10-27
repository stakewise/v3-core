import { ByteVectorType, ContainerType, Type, UintNumberType } from '@chainsafe/ssz'
import { network } from 'hardhat'
import { Buffer } from 'buffer'
import { BigNumber, BytesLike, Contract, Wallet } from 'ethers'
import { arrayify, defaultAbiCoder, parseEther } from 'ethers/lib/utils'
import bls from 'bls-eth-wasm'
import { MerkleTree } from 'merkletreejs'
import keccak256 from 'keccak256'
import { Signers, EthVault, EthOracle } from '../../typechain-types'
import { EIP712Domain, RegisterValidatorSig, RegisterValidatorsSig } from './constants'

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

const DOMAIN_DEPOSIT = Uint8Array.from([3, 0, 0, 0])
const ETH1_ADDRESS_WITHDRAWAL_PREFIX = Uint8Array.from([1])
const GENESIS_FORK_VERSION = arrayify('0x00000000')
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
  flags: boolean[]
  proof: Buffer[]
}

export type EthValidatorsData = {
  root: string
  ipfsHash: string
  tree: MerkleTree
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
  return Buffer.concat([ETH1_ADDRESS_WITHDRAWAL_PREFIX, Buffer.alloc(11), arrayify(vaultAddress)])
}

export async function createValidators(
  depositAmount: BigNumber,
  vaultAddress: string
): Promise<Buffer[]> {
  await bls.init(bls.BLS12_381)

  const withdrawalCredentials = getWithdrawalCredentials(vaultAddress)
  const validators: Buffer[] = []
  for (let i = 0; i < secretKeys.length; i++) {
    const secretKey = new bls.SecretKey()
    secretKey.deserialize(arrayify(secretKeys[i]))
    const publicKey = secretKey.getPublicKey().serialize()

    // create DepositData
    const depositData = {
      pubkey: publicKey,
      withdrawalCredentials,
      amount: depositAmount.div(1000000000).toNumber(), // convert to gwei
      signature: Buffer.alloc(0),
    }
    const domain = computeDomain(DOMAIN_DEPOSIT, GENESIS_FORK_VERSION, ZERO_HASH)
    const signingRoot = computeSigningRoot(DepositMessage, depositData, domain)
    const signature = secretKey.sign(signingRoot).serialize()
    validators.push(Buffer.concat([publicKey, signature]))
  }
  return validators
}

export function appendDepositData(
  validator: Buffer,
  depositAmount: BigNumber,
  vaultAddress: string
): Buffer {
  const withdrawalCredentials = getWithdrawalCredentials(vaultAddress)

  // create DepositData
  const depositData = {
    pubkey: validator.subarray(0, 48),
    withdrawalCredentials,
    amount: depositAmount.div(1000000000).toNumber(), // convert to gwei
    signature: validator.subarray(48, 144),
  }
  return Buffer.concat([validator, DepositData.hashTreeRoot(depositData)])
}

export async function createEthValidatorsData(vault: EthVault): Promise<EthValidatorsData> {
  const validatorDeposit = parseEther('32')
  const validators = (await createValidators(validatorDeposit, vault.address)).sort(Buffer.compare)
  const tree = new MerkleTree(validators, keccak256, {
    hashLeaves: true,
    sortPairs: true,
  })
  const treeRoot = tree.getHexRoot()
  // mock IPFS hash
  const ipfsHash = '/ipfs/' + treeRoot

  return {
    root: treeRoot,
    ipfsHash,
    tree,
    validators: validators.map((v) => appendDepositData(v, validatorDeposit, vault.address)),
  }
}

export function getEthValidatorSigningData(
  validator: Buffer,
  signers: Signers,
  vault: EthVault,
  validatorsRegistryRoot: BytesLike
) {
  return {
    primaryType: 'EthOracle',
    types: { EIP712Domain, EthOracle: RegisterValidatorSig },
    domain: {
      name: 'Signers',
      version: '1',
      chainId: network.config.chainId,
      verifyingContract: signers.address,
    },
    message: {
      validatorsRegistryRoot,
      vault: vault.address,
      validator: keccak256(validator),
    },
  }
}

export function getEthValidatorsSigningData(
  validators: Buffer[],
  signers: Signers,
  vault: EthVault,
  validatorsRegistryRoot: BytesLike
) {
  return {
    primaryType: 'EthOracle',
    types: { EIP712Domain, EthOracle: RegisterValidatorsSig },
    domain: {
      name: 'Signers',
      version: '1',
      chainId: network.config.chainId,
      verifyingContract: signers.address,
    },
    message: {
      validatorsRegistryRoot,
      vault: vault.address,
      validators: keccak256(defaultAbiCoder.encode(['bytes[]'], [validators])),
    },
  }
}

export function getValidatorProof(tree: MerkleTree, validator: Buffer): string[] {
  return tree.getHexProof(keccak256(validator.subarray(0, 144)))
}

export function getValidatorsMultiProof(
  tree: MerkleTree,
  validators: Buffer[]
): ValidatorsMultiProof {
  const leaves = validators.map((val) => keccak256(val.subarray(0, 144)))
  const proof = tree.getMultiProof(leaves)
  const flags = tree.getProofFlags(leaves, proof)
  return { flags, proof }
}

export async function registerEthValidator(
  vault: EthVault,
  signers: Signers,
  oracle: EthOracle,
  validatorsRegistry: Contract,
  operator: Wallet,
  getSignatures: (typedData: any, count?: number) => Buffer
) {
  const validatorsData = await createEthValidatorsData(vault)
  const validatorsRegistryRoot = await validatorsRegistry.get_deposit_root()
  await vault.connect(operator).setValidatorsRoot(validatorsData.root, validatorsData.ipfsHash)
  const validator = validatorsData.validators[0]
  const signingData = getEthValidatorSigningData(validator, signers, vault, validatorsRegistryRoot)
  const signatures = getSignatures(signingData)
  const proof = getValidatorProof(validatorsData.tree, validator)
  await oracle.registerValidator(
    vault.address,
    validatorsRegistryRoot,
    validator,
    signatures,
    proof
  )
}
