import { ethers, waffle } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import { EthVault, IKeeperRewards, Keeper, Oracles } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import snapshotGasCost from './shared/snapshotGasCost'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { setBalance } from './shared/utils'
import { getRewardsRootProof, updateRewardsRoot } from './shared/rewards'
import { registerEthValidator } from './shared/validators'

const createFixtureLoader = waffle.createFixtureLoader

describe('EthVault - multicall', () => {
  const capacity = parseEther('1000')
  const feePercent = 1000
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
    vault = await createVault(admin, {
      capacity,
      validatorsRoot,
      feePercent,
      name,
      symbol,
      metadataIpfsHash,
    })
  })

  it('can update state, redeem and queue for exit', async () => {
    await vault.connect(sender).deposit(sender.address, { value: parseEther('32') })

    // collateralize vault
    await registerEthValidator(vault, oracles, keeper, validatorsRegistry, admin, getSignatures)
    await setBalance(await vault.mevEscrow(), parseEther('10'))

    // update rewards root for the vault
    const vaultReward = parseEther('1')
    const tree = await updateRewardsRoot(keeper, oracles, getSignatures, [
      { reward: vaultReward, vault: vault.address },
    ])

    // retrieve redeemable shares after state update
    const harvestParams: IKeeperRewards.HarvestParamsStruct = {
      rewardsRoot: tree.root,
      reward: vaultReward,
      proof: getRewardsRootProof(tree, { vault: vault.address, reward: vaultReward }),
    }
    let calls: string[] = [
      vault.interface.encodeFunctionData('updateState', [harvestParams]),
      vault.interface.encodeFunctionData('redeemableShares'),
    ]
    const result = await vault.callStatic.multicall(calls)
    const redeemableShares = vault.interface.decodeFunctionResult('redeemableShares', result[1])[0]

    // retrieve withdrawable shares after
    const totalShares = await vault.balanceOf(sender.address)

    // update state, redeem and queue for exit
    calls = [
      vault.interface.encodeFunctionData('updateState', [harvestParams]),
      vault.interface.encodeFunctionData('redeem', [
        redeemableShares,
        sender.address,
        sender.address,
      ]),
      vault.interface.encodeFunctionData('enterExitQueue', [
        totalShares.sub(redeemableShares),
        sender.address,
        sender.address,
      ]),
    ]

    const receipt = await vault.connect(sender).multicall(calls)
    await expect(receipt).to.emit(vault, 'StateUpdated')
    await expect(receipt).to.emit(vault, 'Withdraw')
    await expect(receipt).to.emit(vault, 'ExitQueueEntered')
    await snapshotGasCost(receipt)

    // reverts on error
    calls = [
      vault.interface.encodeFunctionData('updateState', [harvestParams]),
      vault.interface.encodeFunctionData('redeem', [
        totalShares.sub(redeemableShares),
        sender.address,
        sender.address,
      ]),
    ]
    await expect(vault.connect(sender).multicall(calls)).reverted
  })

  it('fails to deposit in multicall', async () => {
    const amount = parseEther('1')
    const calls: string[] = [
      vault.interface.encodeFunctionData('deposit', [sender.address]),
      vault.interface.encodeFunctionData('withdraw', [amount, sender.address, sender.address]),
    ]
    await expect(vault.connect(sender).multicall(calls)).reverted
  })
})
