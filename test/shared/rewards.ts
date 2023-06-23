import { network, waffle } from 'hardhat'
import { BigNumberish, Contract, Wallet } from 'ethers'
import { parseEther, toUtf8Bytes } from 'ethers/lib/utils'
import keccak256 from 'keccak256'
import { StandardMerkleTree } from '@openzeppelin/merkle-tree'
import { Keeper, EthVault } from '../../typechain-types'
import {
  EIP712Domain,
  KeeperRewardsSig,
  MAX_AVG_REWARD_PER_SECOND,
  ONE_DAY,
  REWARDS_DELAY,
  ZERO_ADDRESS,
} from './constants'
import { Buffer } from 'buffer'
import { registerEthValidator } from './validators'
import { increaseTime, setBalance } from './utils'
import { getOraclesSignatures } from './fixtures'

export type RewardsTree = StandardMerkleTree<[string, BigNumberish, BigNumberish]>

export type RewardsUpdate = {
  root: string
  ipfsHash: string
  updateTimestamp: BigNumberish
  avgRewardPerSecond: BigNumberish
  tree: RewardsTree
  signingData: any
}

export type VaultReward = {
  vault: string
  reward: BigNumberish
  unlockedMevReward: BigNumberish
}

function randomIntFromInterval(min, max): number {
  return Math.floor(Math.random() * (max - min + 1) + min)
}

export function getKeeperRewardsUpdateData(
  rewards: VaultReward[],
  keeper: Keeper,
  { nonce = 1, updateTimestamp = '1670255895', avgRewardPerSecond = 1585489600 } = {}
): RewardsUpdate {
  const tree = StandardMerkleTree.of(
    rewards.map((r) => [r.vault, r.reward, r.unlockedMevReward]),
    ['address', 'int160', 'uint160']
  ) as RewardsTree

  const treeRoot = tree.root
  // mock IPFS hash
  const ipfsHash = '/ipfs/' + treeRoot

  return {
    root: treeRoot,
    ipfsHash,
    updateTimestamp,
    avgRewardPerSecond,
    tree,
    signingData: {
      primaryType: 'KeeperRewards',
      types: { EIP712Domain, KeeperRewards: KeeperRewardsSig },
      domain: {
        name: 'KeeperOracles',
        version: '1',
        chainId: network.config.chainId,
        verifyingContract: keeper.address,
      },
      message: {
        rewardsRoot: treeRoot,
        rewardsIpfsHash: keccak256(Buffer.from(toUtf8Bytes(ipfsHash))),
        avgRewardPerSecond,
        updateTimestamp,
        nonce,
      },
    },
  }
}

export async function updateRewards(
  keeper: Keeper,
  rewards: VaultReward[],
  avgRewardPerSecond: number = randomIntFromInterval(1, MAX_AVG_REWARD_PER_SECOND)
): Promise<RewardsTree> {
  const rewardsNonce = await keeper.rewardsNonce()
  const rewardsUpdate = getKeeperRewardsUpdateData(rewards, keeper, {
    nonce: rewardsNonce.toNumber(),
    avgRewardPerSecond,
  })
  await increaseTime(REWARDS_DELAY)
  await keeper.updateRewards({
    rewardsRoot: rewardsUpdate.root,
    avgRewardPerSecond: rewardsUpdate.avgRewardPerSecond,
    updateTimestamp: rewardsUpdate.updateTimestamp,
    rewardsIpfsHash: rewardsUpdate.ipfsHash,
    signatures: getOraclesSignatures(rewardsUpdate.signingData),
  })
  return rewardsUpdate.tree
}

export function getRewardsRootProof(tree: RewardsTree, vaultReward: VaultReward): string[] {
  return tree.getProof([vaultReward.vault, vaultReward.reward, vaultReward.unlockedMevReward])
}

export async function collateralizeEthVault(
  vault: EthVault,
  keeper: Keeper,
  validatorsRegistry: Contract,
  admin: Wallet
): Promise<[string, string[]]> {
  const balanceBefore = await waffle.provider.getBalance(vault.address)
  // register validator
  const validatorDeposit = parseEther('32')
  await vault.connect(admin).deposit(admin.address, ZERO_ADDRESS, { value: validatorDeposit })
  await registerEthValidator(vault, keeper, validatorsRegistry, admin)

  // update rewards tree
  const rewardsTree = await updateRewards(keeper, [
    { vault: vault.address, reward: 0, unlockedMevReward: 0 },
  ])
  const proof = getRewardsRootProof(rewardsTree, {
    vault: vault.address,
    reward: 0,
    unlockedMevReward: 0,
  })

  // exit validator
  const positionTicket = await vault
    .connect(admin)
    .callStatic.enterExitQueue(validatorDeposit, admin.address)
  await vault.connect(admin).enterExitQueue(validatorDeposit, admin.address)
  await setBalance(vault.address, validatorDeposit)

  await vault.updateState({ rewardsRoot: rewardsTree.root, reward: 0, unlockedMevReward: 0, proof })

  // claim exited assets
  const exitQueueIndex = await vault.getExitQueueIndex(positionTicket)
  vault.connect(admin).claimExitedAssets(admin.address, positionTicket, exitQueueIndex)

  await increaseTime(ONE_DAY)
  await setBalance(vault.address, balanceBefore)

  return [rewardsTree.root, proof]
}
