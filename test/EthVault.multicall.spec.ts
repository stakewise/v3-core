import { ethers, waffle } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import { EthVault, IKeeperRewards, Keeper, OwnMevEscrow } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import snapshotGasCost from './shared/snapshotGasCost'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { increaseTime, setBalance } from './shared/utils'
import { getRewardsRootProof, updateRewards } from './shared/rewards'
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

  it('can update state, redeem and queue for exit', async () => {
    const ownMevEscrow = await ethers.getContractFactory('OwnMevEscrow')
    const mevEscrow = ownMevEscrow.attach(await vault.mevEscrow()) as OwnMevEscrow

    // collateralize vault
    await vault.connect(sender).deposit(sender.address, referrer, { value: parseEther('32') })
    await registerEthValidator(vault, keeper, validatorsRegistry, admin)
    await setBalance(mevEscrow.address, parseEther('10'))

    const userShares = await vault.balanceOf(sender.address)

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
      vault.interface.encodeFunctionData('withdrawableAssets'),
      vault.interface.encodeFunctionData('convertToAssets', [userShares]),
    ]
    let result = await vault.callStatic.multicall(calls)
    const availableAssets = vault.interface.decodeFunctionResult('withdrawableAssets', result[1])[0]
    const userAssets = vault.interface.decodeFunctionResult('convertToAssets', result[2])[0]

    // calculate assets that can be withdrawn instantly
    const withdrawAssets = availableAssets.gt(userAssets) ? userAssets : availableAssets

    // calculate assets that must go to the exit queue
    const exitQueueAssets = userAssets.sub(withdrawAssets)

    // convert exit queue assets to shares
    calls = [
      vault.interface.encodeFunctionData('updateState', [harvestParams]),
      vault.interface.encodeFunctionData('convertToShares', [exitQueueAssets]),
      vault.interface.encodeFunctionData('convertToShares', [withdrawAssets]),
    ]
    result = await vault.callStatic.multicall(calls)
    const exitQueueShares = vault.interface.decodeFunctionResult('convertToShares', result[1])[0]
    const withdrawShares = vault.interface.decodeFunctionResult('convertToShares', result[2])[0]

    calls = [vault.interface.encodeFunctionData('updateState', [harvestParams])]

    // add call for instant withdrawal
    calls.push(vault.interface.encodeFunctionData('redeem', [withdrawShares, sender.address]))

    // add call for entering exit queue
    calls.push(
      vault.interface.encodeFunctionData('enterExitQueue', [exitQueueShares, sender.address])
    )

    result = await vault.connect(sender).callStatic.multicall(calls)
    const queueTicket = vault.interface.decodeFunctionResult('enterExitQueue', result[2])[0]

    let receipt = await vault.connect(sender).multicall(calls)
    await expect(receipt).to.emit(keeper, 'Harvested')
    await expect(receipt).to.emit(mevEscrow, 'Harvested')
    await expect(receipt).to.emit(vault, 'Redeemed')
    await expect(receipt).to.emit(vault, 'ExitQueueEntered')
    await snapshotGasCost(receipt)

    // wait for exit queue to complete and withdraw exited assets
    const assetsDropped = await vault.convertToAssets(exitQueueShares)
    await setBalance(vault.address, assetsDropped)
    // wait for exit queue
    await increaseTime(ONE_DAY)
    calls = [vault.interface.encodeFunctionData('updateState', [harvestParams])]
    calls.push(vault.interface.encodeFunctionData('getExitQueueIndex', [queueTicket]))
    result = await vault.connect(sender).callStatic.multicall(calls)
    const checkpointIndex = vault.interface.decodeFunctionResult('getExitQueueIndex', result[1])[0]

    calls = [vault.interface.encodeFunctionData('updateState', [harvestParams])]
    calls.push(
      vault.interface.encodeFunctionData('claimExitedAssets', [queueTicket, checkpointIndex])
    )

    receipt = await vault.connect(sender).multicall(calls)
    await expect(receipt)
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(sender.address, queueTicket, 0, assetsDropped)
    await snapshotGasCost(receipt)

    // reverts on error
    calls = [
      vault.interface.encodeFunctionData('updateState', [harvestParams]),
      vault.interface.encodeFunctionData('redeem', [userShares, sender.address]),
    ]
    await expect(vault.connect(sender).multicall(calls)).reverted
  })

  it('fails to deposit in multicall', async () => {
    const amount = parseEther('1')
    const calls: string[] = [
      vault.interface.encodeFunctionData('deposit', [sender.address, referrer]),
      vault.interface.encodeFunctionData('redeem', [amount, sender.address]),
    ]
    await expect(vault.connect(sender).multicall(calls)).reverted
  })
})
