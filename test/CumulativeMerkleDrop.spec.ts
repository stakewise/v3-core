import { ethers } from 'hardhat'
import { BigNumberish, Wallet } from 'ethers'
import { CumulativeMerkleDrop, ERC20Mock, ERC20Mock__factory } from '../typechain-types'
import { createCumulativeMerkleDrop } from './shared/fixtures'
import { StandardMerkleTree } from '@openzeppelin/merkle-tree'
import { expect } from './shared/expect'
import snapshotGasCost from './shared/snapshotGasCost'
import { PANIC_CODES } from './shared/constants'

type RewardsTree = StandardMerkleTree<[string, BigNumberish]>

describe('CumulativeMerkleDrop', () => {
  const proofsIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  const rewards: { address: string; reward: bigint }[] = [
    { address: '0x5E0375cFD64e036b37f74EbD213B061a0fFd6CC0', reward: 283n },
    { address: '0x3D238CccC9839f012ee613D1076F747093A25F16', reward: 649n },
    { address: '0xb12F7f27A07AB869761FF2bD11943db317a06466', reward: 779n },
    { address: '0x267a0909ea6043550D7054957061dC01eDd2915F', reward: 573n },
    { address: '0x03079134787b4570952Eacb53Bef82a7AF773fED', reward: 959n },
    { address: '0x704e14dFf77cdA4155BBC7b6AA8d3B39810aAE91', reward: 563n },
    { address: '0xC1016a99a8b37fDE1cFddf638f3d8Ec5B14c7d78', reward: 444n },
    { address: '0x6aBb7fFd8ad5770A90640ce7ca7647fA98a48702', reward: 172n },
    { address: '0x6c9A2c104D10fcA6510eF4B2c1E778aA94b50A5a', reward: 969n },
    { address: '0x408bdc9EF95A89F3B200eCb02dffEFEb87650da4', reward: 327n },
  ]
  const tree: RewardsTree = StandardMerkleTree.of(
    rewards.map((r) => [r.address, r.reward]),
    ['address', 'uint256']
  ) as RewardsTree
  let dao: Wallet, sender: Wallet
  let merkleDrop: CumulativeMerkleDrop, token: ERC20Mock

  beforeEach('deploy fixtures', async () => {
    ;[dao, sender] = await (ethers as any).getSigners()
    const factory = await ethers.getContractFactory('ERC20Mock')
    const contract = await factory.deploy()
    token = ERC20Mock__factory.connect(await contract.getAddress(), dao)
    merkleDrop = await createCumulativeMerkleDrop(await token.getAddress(), dao)

    let totalReward = 0n
    for (let i = 0; i < 10; i++) {
      totalReward += rewards[i].reward
    }
    await token.mint(await merkleDrop.getAddress(), totalReward)
  })

  describe('set merkle root', () => {
    it('fails for not owner', async () => {
      await expect(
        merkleDrop.connect(sender).setMerkleRoot(tree.root, proofsIpfsHash)
      ).revertedWithCustomError(merkleDrop, 'OwnableUnauthorizedAccount')
    })

    it('works for owner', async () => {
      const receipt = await merkleDrop.connect(dao).setMerkleRoot(tree.root, proofsIpfsHash)
      expect(await merkleDrop.merkleRoot()).to.eq(tree.root)
      await expect(receipt)
        .to.emit(merkleDrop, 'MerkleRootUpdated')
        .withArgs(tree.root, proofsIpfsHash)
      await snapshotGasCost(receipt)
    })
  })

  describe('claim', () => {
    beforeEach('set merkle root', async () => {
      await merkleDrop.connect(dao).setMerkleRoot(tree.root, proofsIpfsHash)
    })

    it('fails with invalid proof', async () => {
      const reward = rewards[0]
      await expect(
        merkleDrop.claim(
          reward.address,
          reward.reward,
          tree.getProof([rewards[1].address, rewards[1].reward])
        )
      ).revertedWithCustomError(merkleDrop, 'InvalidProof')
    })

    it('reverts with cumulative amount less than previous', async () => {
      let reward = rewards[0]
      await merkleDrop.claim(
        reward.address,
        reward.reward,
        tree.getProof([reward.address, reward.reward])
      )
      const newRewards = [{ address: reward.address, reward: reward.reward - 1n }]
      const newTree = StandardMerkleTree.of(
        newRewards.map((r) => [r.address, r.reward]),
        ['address', 'uint256']
      ) as RewardsTree
      await merkleDrop.connect(dao).setMerkleRoot(newTree.root, proofsIpfsHash)

      reward = newRewards[0]
      await expect(
        merkleDrop.claim(
          reward.address,
          reward.reward,
          newTree.getProof([reward.address, reward.reward])
        )
      ).revertedWithPanic(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
    })

    it('works with valid proof', async () => {
      const reward = rewards[0]
      const receipt = await merkleDrop.claim(
        reward.address,
        reward.reward,
        tree.getProof([reward.address, reward.reward])
      )
      await expect(receipt).to.emit(merkleDrop, 'Claimed').withArgs(reward.address, reward.reward)
      await snapshotGasCost(receipt)

      // fails to claim second time
      await expect(
        merkleDrop.claim(
          reward.address,
          reward.reward,
          tree.getProof([reward.address, reward.reward])
        )
      ).revertedWithCustomError(merkleDrop, 'AlreadyClaimed')
    })
  })
})
