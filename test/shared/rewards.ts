import { network } from 'hardhat'
import { BigNumberish } from 'ethers'
import { toUtf8Bytes } from 'ethers/lib/utils'
import keccak256 from 'keccak256'
import { StandardMerkleTree } from '@openzeppelin/merkle-tree'
import { Keeper, Oracles } from '../../typechain-types'
import { EIP712Domain, KeeperSig } from './constants'
import { Buffer } from 'buffer'

export type RewardsTree = StandardMerkleTree<[string, BigNumberish]>

export type RewardsRoot = {
  root: string
  ipfsHash: string
  tree: RewardsTree
  signingData: any
}

export type VaultReward = {
  vault: string
  reward: BigNumberish
}

export function createVaultRewardsRoot(
  rewards: VaultReward[],
  oracles: Oracles,
  nonce = 0
): RewardsRoot {
  const tree = StandardMerkleTree.of(
    rewards.map((r) => [r.vault, r.reward]),
    ['address', 'int160']
  ) as RewardsTree

  const treeRoot = tree.root
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
        name: 'Oracles',
        version: '1',
        chainId: network.config.chainId,
        verifyingContract: oracles.address,
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
  oracles: Oracles,
  getSignatures: (typedData: any, count?: number) => Buffer,
  rewards: VaultReward[]
): Promise<RewardsTree> {
  const rewardsNonce = await keeper.rewardsNonce()
  const rewardsRoot = createVaultRewardsRoot(rewards, oracles, rewardsNonce.toNumber())
  await keeper.setRewardsRoot(
    rewardsRoot.root,
    rewardsRoot.ipfsHash,
    getSignatures(rewardsRoot.signingData)
  )
  return rewardsRoot.tree
}

export function getRewardsRootProof(tree: RewardsTree, vaultReward: VaultReward): string[] {
  return tree.getProof([vaultReward.vault, vaultReward.reward])
}
