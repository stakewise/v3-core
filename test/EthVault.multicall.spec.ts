import { ethers, waffle } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import { EthVault, IKeeperRewards, Keeper, Oracles, OwnMevEscrow } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import snapshotGasCost from './shared/snapshotGasCost'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { increaseTime, setBalance } from './shared/utils'
import { getRewardsRootProof, updateRewardsRoot } from './shared/rewards'
import { registerEthValidator } from './shared/validators'
import { ONE_DAY } from './shared/constants'

const createFixtureLoader = waffle.createFixtureLoader

describe('EthVault - multicall', () => {
  const capacity = parseEther('1000')
  const feePercent = 1000
  const referrer = '0x' + '1'.repeat(40)
  const name = 'SW ETH Vault'
  const symbol = 'SW-ETH-1'
  const validatorsRoot = '0x059a8487a1ce461e9670c4646ef85164ae8791613866d28c972fb351dc45c606'
  const metadataIpfsHash = '/ipfs/QmanU2bk9VsJuxhBmvfgXaC44fXpcC8DNHNxPZKMpNXo37'

  let sender: Wallet, admin: Wallet, dao: Wallet
  let vault: EthVault, keeper: Keeper, oracles: Oracles, validatorsRegistry: Contract

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createVault']
  let getSignatures: ThenArg<ReturnType<typeof ethVaultFixture>>['getSignatures']

  before('create fixture loader', async () => {
    ;[sender, admin, dao] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([dao])
  })

  beforeEach('deploy fixture', async () => {
    ;({ createVault, keeper, oracles, validatorsRegistry, getSignatures } = await loadFixture(
      ethVaultFixture
    ))
    vault = await createVault(
      admin,
      {
        capacity,
        validatorsRoot,
        feePercent,
        name,
        symbol,
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
    await registerEthValidator(vault, oracles, keeper, validatorsRegistry, admin, getSignatures)
    await setBalance(mevEscrow.address, parseEther('10'))

    const userShares = await vault.balanceOf(sender.address)

    // update rewards root for the vault
    const vaultReward = parseEther('1')
    const tree = await updateRewardsRoot(keeper, oracles, getSignatures, [
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
    ]
    result = await vault.callStatic.multicall(calls)
    const exitQueueShares = vault.interface.decodeFunctionResult('convertToShares', result[1])[0]

    calls = [vault.interface.encodeFunctionData('updateState', [harvestParams])]

    // add call for instant withdrawal
    calls.push(
      vault.interface.encodeFunctionData('withdraw', [
        withdrawAssets,
        sender.address,
        sender.address,
      ])
    )

    // add call for entering exit queue
    calls.push(
      vault.interface.encodeFunctionData('enterExitQueue', [
        exitQueueShares,
        sender.address,
        sender.address,
      ])
    )

    result = await vault.connect(sender).callStatic.multicall(calls)
    const exitQueueCounter = vault.interface.decodeFunctionResult('enterExitQueue', result[2])[0]

    let receipt = await vault.connect(sender).multicall(calls)
    await expect(receipt).to.emit(keeper, 'Harvested')
    await expect(receipt).to.emit(mevEscrow, 'Harvested')
    await expect(receipt).to.emit(vault, 'Withdraw')
    await expect(receipt).to.emit(vault, 'ExitQueueEntered')
    await snapshotGasCost(receipt)

    // wait for exit queue to complete and withdraw exited assets
    const assetsDropped = await vault.convertToAssets(exitQueueShares)
    await setBalance(vault.address, assetsDropped)
    // wait for exit queue
    await increaseTime(ONE_DAY)
    calls = [vault.interface.encodeFunctionData('updateState', [harvestParams])]
    calls.push(vault.interface.encodeFunctionData('getCheckpointIndex', [exitQueueCounter]))
    result = await vault.connect(sender).callStatic.multicall(calls)
    const checkpointIndex = vault.interface.decodeFunctionResult('getCheckpointIndex', result[1])[0]

    calls = [vault.interface.encodeFunctionData('updateState', [harvestParams])]
    calls.push(
      vault.interface.encodeFunctionData('claimExitedAssets', [
        sender.address,
        exitQueueCounter,
        checkpointIndex,
      ])
    )

    receipt = await vault.connect(sender).multicall(calls)
    await expect(receipt)
      .to.emit(vault, 'ExitedAssetsClaimed')
      .withArgs(sender.address, sender.address, exitQueueCounter, 0, assetsDropped)
    await snapshotGasCost(receipt)

    // reverts on error
    calls = [
      vault.interface.encodeFunctionData('updateState', [harvestParams]),
      vault.interface.encodeFunctionData('redeem', [userShares, sender.address, sender.address]),
    ]
    await expect(vault.connect(sender).multicall(calls)).reverted
  })

  it('fails to deposit in multicall', async () => {
    const amount = parseEther('1')
    const calls: string[] = [
      vault.interface.encodeFunctionData('deposit', [sender.address, referrer]),
      vault.interface.encodeFunctionData('withdraw', [amount, sender.address, sender.address]),
    ]
    await expect(vault.connect(sender).multicall(calls)).reverted
  })
})
