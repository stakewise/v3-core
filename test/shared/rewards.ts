import { ethers, network } from 'hardhat'
import { Contract, Signer } from 'ethers'
import { StandardMerkleTree } from '@openzeppelin/merkle-tree'
import { EthVault, IKeeperRewards, Keeper } from '../../typechain-types'
import {
  EIP712Domain,
  EXITING_ASSETS_MIN_DELAY,
  KeeperRewardsSig,
  MAX_AVG_REWARD_PER_SECOND,
  ONE_DAY,
  ORACLES,
  REWARDS_DELAY,
  ZERO_ADDRESS,
} from './constants'
import { registerEthValidator } from './validators'
import { extractExitPositionTicket, getBlockTimestamp, increaseTime, setBalance } from './utils'
import { getOraclesSignatures } from './fixtures'

export type RewardsTree = StandardMerkleTree<[string, bigint, bigint]>

export type RewardsUpdate = {
  root: string
  ipfsHash: string
  updateTimestamp: number
  avgRewardPerSecond: number
  tree: RewardsTree
  signingData: any
}

export type VaultReward = {
  vault: string
  reward: bigint
  unlockedMevReward: bigint
}

function randomIntFromInterval(min, max): number {
  return Math.floor(Math.random() * (max - min + 1) + min)
}

export async function getKeeperRewardsUpdateData(
  rewards: VaultReward[],
  keeper: Keeper,
  { nonce = 1, updateTimestamp = 1670255895, avgRewardPerSecond = 1585489600 } = {}
): Promise<RewardsUpdate> {
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
        verifyingContract: await keeper.getAddress(),
      },
      message: {
        rewardsRoot: treeRoot,
        rewardsIpfsHash: ipfsHash,
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
  const rewardsUpdate = await getKeeperRewardsUpdateData(rewards, keeper, {
    nonce: Number(rewardsNonce),
    avgRewardPerSecond,
  })
  await increaseTime(REWARDS_DELAY)
  const oracle = new ethers.Wallet(ORACLES[0].toString('hex'), ethers.provider)
  await setBalance(oracle.address, ethers.parseEther('2000'))

  await keeper.connect(oracle).updateRewards({
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
  admin: Signer
) {
  const vaultAddress = await vault.getAddress()
  const balanceBefore = await ethers.provider.getBalance(vaultAddress)
  const adminAddr = await admin.getAddress()

  // register validator
  const validatorDeposit = ethers.parseEther('32')
  await vault.connect(admin).deposit(adminAddr, ZERO_ADDRESS, { value: validatorDeposit })
  await registerEthValidator(vault, keeper, validatorsRegistry, admin)

  // update rewards tree
  const rewardsTree = await updateRewards(keeper, [
    { vault: vaultAddress, reward: 0n, unlockedMevReward: 0n },
  ])
  const proof = getRewardsRootProof(rewardsTree, {
    vault: vaultAddress,
    reward: 0n,
    unlockedMevReward: 0n,
  })

  // exit validator
  const response = await vault.connect(admin).enterExitQueue(validatorDeposit, adminAddr)
  const positionTicket = await extractExitPositionTicket(response)
  const timestamp = await getBlockTimestamp(response)

  await increaseTime(EXITING_ASSETS_MIN_DELAY)
  await setBalance(vaultAddress, validatorDeposit)

  await vault.updateState({
    rewardsRoot: rewardsTree.root,
    reward: 0n,
    unlockedMevReward: 0n,
    proof,
  })

  // claim exited assets
  const exitQueueIndex = await vault.getExitQueueIndex(positionTicket)
  await vault.connect(admin).claimExitedAssets(positionTicket, timestamp, exitQueueIndex)

  await increaseTime(ONE_DAY)
  await setBalance(vaultAddress, balanceBefore)
}

export async function setAvgRewardPerSecond(
  dao: Signer,
  vault: EthVault,
  keeper: Keeper,
  avgRewardPerSecond: number
) {
  const vaultAddress = await vault.getAddress()
  const tree = await updateRewards(
    keeper,
    [{ vault: vaultAddress, reward: 0n, unlockedMevReward: 0n }],
    avgRewardPerSecond
  )
  const harvestParams: IKeeperRewards.HarvestParamsStruct = {
    rewardsRoot: tree.root,
    reward: 0n,
    unlockedMevReward: 0n,
    proof: getRewardsRootProof(tree, {
      vault: vaultAddress,
      unlockedMevReward: 0n,
      reward: 0n,
    }),
  }
  await vault.connect(dao).updateState(harvestParams)
}
