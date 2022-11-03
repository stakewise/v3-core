import { MerkleTree } from 'merkletreejs'
import { network } from 'hardhat'
import { BigNumberish } from 'ethers'
import { defaultAbiCoder, toUtf8Bytes } from 'ethers/lib/utils'
import keccak256 from 'keccak256'
import { Signers, Keeper } from '../../typechain-types'
import { EIP712Domain, KeeperSig } from './constants'

export type RewardsRoot = {
  root: string
  ipfsHash: string
  tree: MerkleTree
  signingData: any
}

export type VaultReward = {
  vault: string
  reward: BigNumberish
}

export function createVaultRewardsRoot(
  rewards: VaultReward[],
  signers: Signers,
  nonce = 0
): RewardsRoot {
  const elements = rewards.map((r) =>
    defaultAbiCoder.encode(['address', 'int160'], [r.vault, r.reward])
  )
  const tree = new MerkleTree(elements, keccak256, { hashLeaves: true, sortPairs: true })
  const treeRoot = tree.getHexRoot()
  // mock IPFS hash
  const ipfsHash = '/ipfs/' + treeRoot

  return {
    root: treeRoot,
    ipfsHash,
    tree,
    signingData: {
      primaryType: 'Keeper',
      types: { EIP712Domain, Keeper: KeeperSig },
      domain: {
        name: 'Signers',
        version: '1',
        chainId: network.config.chainId,
        verifyingContract: signers.address,
      },
      message: {
        rewardsRoot: treeRoot,
        rewardsIpfsHash: keccak256(Buffer.from(toUtf8Bytes(ipfsHash))),
        nonce,
      },
    },
  }
}

export async function updateRewardsRoot(
  keeper: Keeper,
  signers: Signers,
  getSignatures: (typedData: any, count?: number) => Buffer,
  rewards: VaultReward[]
): Promise<MerkleTree> {
  const rewardsNonce = await keeper.rewardsNonce()
  const rewardsRoot = createVaultRewardsRoot(rewards, signers, rewardsNonce.toNumber())
  await keeper.setRewardsRoot(
    rewardsRoot.root,
    rewardsRoot.ipfsHash,
    getSignatures(rewardsRoot.signingData)
  )
  return rewardsRoot.tree
}

export function getRewardsRootProof(tree: MerkleTree, vaultReward: VaultReward): string[] {
  return tree.getHexProof(
    keccak256(
      defaultAbiCoder.encode(['address', 'int160'], [vaultReward.vault, vaultReward.reward])
    )
  )
}
