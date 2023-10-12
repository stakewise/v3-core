import { ethers } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  EthVault,
  IKeeperRewards,
  Keeper,
  MulticallMock,
  OwnMevEscrow__factory,
} from '../typechain-types'
import { ThenArg } from '../helpers/types'
import snapshotGasCost from './shared/snapshotGasCost'
import { createMulticallMock, ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import {
  extractExitPositionTicket,
  getBlockTimestamp,
  getLatestBlockTimestamp,
  increaseTime,
  setBalance,
} from './shared/utils'
import { collateralizeEthVault, getRewardsRootProof, updateRewards } from './shared/rewards'
import { registerEthValidator } from './shared/validators'
import { ONE_DAY } from './shared/constants'

describe('EthVault - multicall', () => {
  const capacity = ethers.parseEther('1000')
  const feePercent = 1000
  const referrer = '0x' + '1'.repeat(40)
  const metadataIpfsHash = '/ipfs/QmanU2bk9VsJuxhBmvfgXaC44fXpcC8DNHNxPZKMpNXo37'

  let sender: Wallet, admin: Wallet
  let vault: EthVault, keeper: Keeper, validatorsRegistry: Contract

  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVault']

  beforeEach('deploy fixture', async () => {
    ;[sender, admin] = (await (ethers as any).getSigners()).slice(1, 3)
    ;({
      createEthVault: createVault,
      keeper,
      validatorsRegistry,
    } = await loadFixture(ethVaultFixture))
    vault = await createVault(
      admin,
      {
        capacity,
        feePercent,
        metadataIpfsHash,
      },
      true
    )
  })

  it('can update state and queue for exit', async () => {
    const mevEscrow = OwnMevEscrow__factory.connect(await vault.mevEscrow(), sender)

    // collateralize vault
    await vault
      .connect(sender)
      .deposit(sender.address, referrer, { value: ethers.parseEther('32') })
    await registerEthValidator(vault, keeper, validatorsRegistry, admin)
    await setBalance(await mevEscrow.getAddress(), ethers.parseEther('10'))

    const userShares = await vault.getShares(sender.address)

    // update rewards root for the vault
    const vaultReward = ethers.parseEther('1')
    const tree = await updateRewards(keeper, [
      { reward: vaultReward, unlockedMevReward: 0n, vault: await vault.getAddress() },
    ])

    // retrieve redeemable shares after state update
    const harvestParams: IKeeperRewards.HarvestParamsStruct = {
      rewardsRoot: tree.root,
      reward: vaultReward,
      unlockedMevReward: 0n,
      proof: getRewardsRootProof(tree, {
        vault: await vault.getAddress(),
        reward: vaultReward,
        unlockedMevReward: 0n,
      }),
    }

    // fetch available assets and user assets after state update
    let calls: string[] = [
      vault.interface.encodeFunctionData('updateState', [harvestParams]),
      vault.interface.encodeFunctionData('convertToAssets', [userShares]),
    ]
    let result = await vault.multicall.staticCall(calls)
    const userAssets = vault.interface.decodeFunctionResult('convertToAssets', result[1])[0]

    // convert exit queue assets to shares
    calls = [
      vault.interface.encodeFunctionData('updateState', [harvestParams]),
      vault.interface.encodeFunctionData('convertToShares', [userAssets]),
    ]
    result = await vault.multicall.staticCall(calls)
    const exitQueueShares = vault.interface.decodeFunctionResult('convertToShares', result[1])[0]

    calls = [vault.interface.encodeFunctionData('updateState', [harvestParams])]

    // add call for entering exit queue
    calls.push(
      vault.interface.encodeFunctionData('enterExitQueue', [exitQueueShares, sender.address])
    )

    await updateRewards(keeper, [
      { reward: vaultReward, unlockedMevReward: 0n, vault: await vault.getAddress() },
    ])

    let receipt = await vault.connect(sender).multicall(calls)
    const queueTicket = await extractExitPositionTicket(receipt)
    const timestamp = await getBlockTimestamp(receipt)
    await expect(receipt).to.emit(keeper, 'Harvested')
    await expect(receipt).to.emit(mevEscrow, 'Harvested')
    await expect(receipt).to.emit(vault, 'ExitQueueEntered')
    await snapshotGasCost(receipt)

    // wait for exit queue to complete and withdraw exited assets
    await setBalance(await vault.getAddress(), userAssets)

    // wait for exit queue
    await increaseTime(ONE_DAY)
    await updateRewards(keeper, [
      { reward: vaultReward, unlockedMevReward: 0n, vault: await vault.getAddress() },
    ])

    calls = [vault.interface.encodeFunctionData('updateState', [harvestParams])]
    calls.push(vault.interface.encodeFunctionData('getExitQueueIndex', [queueTicket]))
    result = await vault.connect(sender).multicall.staticCall(calls)
    const checkpointIndex = vault.interface.decodeFunctionResult('getExitQueueIndex', result[1])[0]

    calls = [vault.interface.encodeFunctionData('updateState', [harvestParams])]
    calls.push(
      vault.interface.encodeFunctionData('claimExitedAssets', [
        queueTicket,
        timestamp,
        checkpointIndex,
      ])
    )

    receipt = await vault.connect(sender).multicall(calls)
    await expect(receipt)
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(sender.address, queueTicket, 0, userAssets - 1n) // 1 wei is left in the vault
    await snapshotGasCost(receipt)
  })

  it('fails to deposit in multicall', async () => {
    const calls: string[] = [
      vault.interface.encodeFunctionData('deposit', [sender.address, referrer]),
    ]
    await expect(vault.connect(sender).multicall(calls)).reverted
  })

  describe('flash loan', () => {
    let multicallMock: MulticallMock

    beforeEach(async () => {
      multicallMock = await createMulticallMock()
    })

    it('fails to deposit, enter exit queue, update state and claim in one transaction', async () => {
      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
      expect(await vault.isStateUpdateRequired()).to.eq(false)
      expect(await keeper.canHarvest(await vault.getAddress())).to.eq(false)

      const vaultReward = ethers.parseEther('1')
      const tree = await updateRewards(keeper, [
        { reward: vaultReward, unlockedMevReward: 0n, vault: await vault.getAddress() },
      ])
      await setBalance(await vault.mevEscrow(), ethers.parseEther('1'))
      expect(await vault.isStateUpdateRequired()).to.eq(false)
      expect(await keeper.canHarvest(await vault.getAddress())).to.eq(true)

      const harvestParams: IKeeperRewards.HarvestParamsStruct = {
        rewardsRoot: tree.root,
        reward: vaultReward,
        unlockedMevReward: 0n,
        proof: getRewardsRootProof(tree, {
          vault: await vault.getAddress(),
          reward: vaultReward,
          unlockedMevReward: 0n,
        }),
      }

      const amount = ethers.parseEther('1')
      const currentBlockTimestamp = await getLatestBlockTimestamp()
      await ethers.provider.send('evm_setNextBlockTimestamp', [currentBlockTimestamp + 1])
      const calls = [
        {
          target: await vault.getAddress(),
          isPayable: true,
          callData: vault.interface.encodeFunctionData('deposit', [
            await multicallMock.getAddress(),
            referrer,
          ]),
        },
        {
          target: await vault.getAddress(),
          isPayable: false,
          callData: vault.interface.encodeFunctionData('enterExitQueue', [
            amount,
            await multicallMock.getAddress(),
          ]),
        },
        {
          target: await vault.getAddress(),
          isPayable: false,
          callData: vault.interface.encodeFunctionData('updateState', [harvestParams]),
        },
        {
          target: await vault.getAddress(),
          isPayable: false,
          callData: vault.interface.encodeFunctionData('claimExitedAssets', [
            ethers.parseEther('32'),
            currentBlockTimestamp + 1,
            1,
          ]),
        },
      ]
      await expect(multicallMock.connect(sender).aggregate(calls, { value: amount })).reverted
    })
  })
})
