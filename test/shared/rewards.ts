import { network, waffle } from 'hardhat'
import { BigNumberish, Contract, Wallet } from 'ethers'
import { parseEther, toUtf8Bytes } from 'ethers/lib/utils'
import keccak256 from 'keccak256'
import { StandardMerkleTree } from '@openzeppelin/merkle-tree'
import { Keeper, EthVault, Oracles } from '../../typechain-types'
import { EIP712Domain, KeeperRewardsSig, ONE_DAY, ORACLES } from './constants'
import { Buffer } from 'buffer'
import { registerEthValidator } from './validators'
import { increaseTime, setBalance } from './utils'

export type RewardsTree = StandardMerkleTree<[string, BigNumberish]>

export type RewardsRoot = {
  root: string
  ipfsHash: string
  updateTimestamp: number
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
  updateTimestamp = 1670255895,
  nonce = 1
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
    updateTimestamp,
    tree,
    signingData: {
      primaryType: 'KeeperRewards',
      types: { EIP712Domain, KeeperRewards: KeeperRewardsSig },
      domain: {
        name: 'Oracles',
        version: '1',
        chainId: network.config.chainId,
        verifyingContract: oracles.address,
      },
      message: {
        rewardsRoot: treeRoot,
        rewardsIpfsHash: keccak256(Buffer.from(toUtf8Bytes(ipfsHash))),
        updateTimestamp,
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
  const rewardsRoot = createVaultRewardsRoot(rewards, oracles, 1670257866, rewardsNonce.toNumber())
  await keeper.setRewardsRoot({
    rewardsRoot: rewardsRoot.root,
    updateTimestamp: rewardsRoot.updateTimestamp,
    rewardsIpfsHash: rewardsRoot.ipfsHash,
    signatures: getSignatures(rewardsRoot.signingData),
  })
  return rewardsRoot.tree
}

export function getRewardsRootProof(tree: RewardsTree, vaultReward: VaultReward): string[] {
  return tree.getProof([vaultReward.vault, vaultReward.reward])
}

export async function collateralizeEthVault(
  vault: EthVault,
  oracles: Oracles,
  keeper: Keeper,
  validatorsRegistry: Contract,
  admin: Wallet,
  getSignatures: (typedData: any, count?: number) => Buffer
): Promise<[string, string[]]> {
  const balanceBefore = await waffle.provider.getBalance(vault.address)
  // register validator
  const validatorDeposit = parseEther('32')
  await vault.connect(admin).deposit(admin.address, { value: validatorDeposit })
  await registerEthValidator(vault, oracles, keeper, validatorsRegistry, admin, getSignatures)

  // update rewards tree
  const rewardsTree = await updateRewardsRoot(keeper, oracles, getSignatures, [
    { vault: vault.address, reward: 0 },
  ])
  const proof = getRewardsRootProof(rewardsTree, { vault: vault.address, reward: 0 })

  // exit validator
  const exitQueueId = await vault
    .connect(admin)
    .callStatic.enterExitQueue(validatorDeposit, admin.address, admin.address)
  await vault.connect(admin).enterExitQueue(validatorDeposit, admin.address, admin.address)
  await setBalance(vault.address, validatorDeposit)

  await vault.updateState({ rewardsRoot: rewardsTree.root, reward: 0, proof })

  // claim exited assets
  const checkpointIndex = await vault.getCheckpointIndex(exitQueueId)
  vault.connect(admin).claimExitedAssets(admin.address, exitQueueId, checkpointIndex)

  await increaseTime(ONE_DAY)
  await setBalance(vault.address, balanceBefore)

  return [rewardsTree.root, proof]
}
