import { ethers, waffle } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import { EthVault, IKeeperRewards, Keeper, MulticallMock, OwnMevEscrow } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import snapshotGasCost from './shared/snapshotGasCost'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { extractExitPositionTicket, increaseTime, setBalance } from './shared/utils'
import { collateralizeEthVault, getRewardsRootProof, updateRewards } from './shared/rewards'
import { registerEthValidator } from './shared/validators'
import { ONE_DAY } from './shared/constants'

const createFixtureLoader = waffle.createFixtureLoader

describe('EthVault - multicall', () => {
  const capacity = parseEther('1000')
  const feePercent = 1000
  const referrer = '0x' + '1'.repeat(40)
  const metadataIpfsHash = '/ipfs/QmanU2bk9VsJuxhBmvfgXaC44fXpcC8DNHNxPZKMpNXo37'

  let sender: Wallet, admin: Wallet, dao: Wallet
  let vault: EthVault, keeper: Keeper, validatorsRegistry: Contract

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVault']

  before('create fixture loader', async () => {
    ;[sender, admin, dao] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([dao])
  })

  beforeEach('deploy fixture', async () => {
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
    const ownMevEscrow = await ethers.getContractFactory('OwnMevEscrow')
    const mevEscrow = ownMevEscrow.attach(await vault.mevEscrow()) as OwnMevEscrow

    // collateralize vault
    await vault.connect(sender).deposit(sender.address, referrer, { value: parseEther('32') })
    await registerEthValidator(vault, keeper, validatorsRegistry, admin)
    await setBalance(mevEscrow.address, parseEther('10'))

    const userShares = await vault.getShares(sender.address)

    // update rewards root for the vault
    const vaultReward = parseEther('1')
    const tree = await updateRewards(keeper, [
      { reward: vaultReward, unlockedMevReward: 0, vault: vault.address },
    ])

    // retrieve redeemable shares after state update
    const harvestParams: IKeeperRewards.HarvestParamsStruct = {
      rewardsRoot: tree.root,
      reward: vaultReward,
      unlockedMevReward: 0,
      proof: getRewardsRootProof(tree, {
        vault: vault.address,
        reward: vaultReward,
        unlockedMevReward: 0,
      }),
    }

    // fetch available assets and user assets after state update
    let calls: string[] = [
      vault.interface.encodeFunctionData('updateState', [harvestParams]),
      vault.interface.encodeFunctionData('convertToAssets', [userShares]),
    ]
    let result = await vault.callStatic.multicall(calls)
    const userAssets = vault.interface.decodeFunctionResult('convertToAssets', result[1])[0]

    // convert exit queue assets to shares
    calls = [
      vault.interface.encodeFunctionData('updateState', [harvestParams]),
      vault.interface.encodeFunctionData('convertToShares', [userAssets]),
    ]
    result = await vault.callStatic.multicall(calls)
    const exitQueueShares = vault.interface.decodeFunctionResult('convertToShares', result[1])[0]

    calls = [vault.interface.encodeFunctionData('updateState', [harvestParams])]

    // add call for entering exit queue
    calls.push(
      vault.interface.encodeFunctionData('enterExitQueue', [exitQueueShares, sender.address])
    )

    await updateRewards(keeper, [
      { reward: vaultReward, unlockedMevReward: 0, vault: vault.address },
    ])

    let receipt = await vault.connect(sender).multicall(calls)
    const queueTicket = extractExitPositionTicket(await receipt.wait())
    const timestamp = (await ethers.provider.getBlock((await receipt.wait()).blockNumber)).timestamp
    await expect(receipt).to.emit(keeper, 'Harvested')
    await expect(receipt).to.emit(mevEscrow, 'Harvested')
    await expect(receipt).to.emit(vault, 'ExitQueueEntered')
    await snapshotGasCost(receipt)

    // wait for exit queue to complete and withdraw exited assets
    await setBalance(vault.address, userAssets)

    // wait for exit queue
    await increaseTime(ONE_DAY)
    await updateRewards(keeper, [
      { reward: vaultReward, unlockedMevReward: 0, vault: vault.address },
    ])

    calls = [vault.interface.encodeFunctionData('updateState', [harvestParams])]
    calls.push(vault.interface.encodeFunctionData('getExitQueueIndex', [queueTicket]))
    result = await vault.connect(sender).callStatic.multicall(calls)
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
      .withArgs(sender.address, queueTicket, 0, userAssets.sub(1)) // 1 wei is left in the vault
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
      const multicallMockFactory = await ethers.getContractFactory('MulticallMock')
      multicallMock = (await multicallMockFactory.deploy()) as MulticallMock
    })

    it('fails to deposit, enter exit queue, update state and claim in one transaction', async () => {
      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
      expect(await vault.isStateUpdateRequired()).to.eq(false)
      expect(await keeper.canHarvest(vault.address)).to.eq(false)

      const vaultReward = parseEther('1')
      const tree = await updateRewards(keeper, [
        { reward: vaultReward, unlockedMevReward: 0, vault: vault.address },
      ])
      await setBalance(await vault.mevEscrow(), parseEther('1'))
      expect(await vault.isStateUpdateRequired()).to.eq(false)
      expect(await keeper.canHarvest(vault.address)).to.eq(true)

      const harvestParams: IKeeperRewards.HarvestParamsStruct = {
        rewardsRoot: tree.root,
        reward: vaultReward,
        unlockedMevReward: 0,
        proof: getRewardsRootProof(tree, {
          vault: vault.address,
          reward: vaultReward,
          unlockedMevReward: 0,
        }),
      }

      const amount = parseEther('1')
      const currentBlockTimestamp = (await ethers.provider.getBlock('latest')).timestamp
      await waffle.provider.send('evm_setNextBlockTimestamp', [currentBlockTimestamp + 1])
      const calls = [
        {
          target: vault.address,
          isPayable: true,
          callData: vault.interface.encodeFunctionData('deposit', [
            multicallMock.address,
            referrer,
          ]),
        },
        {
          target: vault.address,
          isPayable: false,
          callData: vault.interface.encodeFunctionData('enterExitQueue', [
            amount,
            multicallMock.address,
          ]),
        },
        {
          target: vault.address,
          isPayable: false,
          callData: vault.interface.encodeFunctionData('updateState', [harvestParams]),
        },
        {
          target: vault.address,
          isPayable: false,
          callData: vault.interface.encodeFunctionData('claimExitedAssets', [
            parseEther('32'),
            currentBlockTimestamp + 1,
            1,
          ]),
        },
      ]
      await expect(multicallMock.connect(sender).aggregate(calls, { value: amount })).reverted
    })
  })
})
