import { ethers, waffle } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { hexlify, parseEther } from 'ethers/lib/utils'
import { EthPrivErc20Vault, Keeper, IKeeperRewards } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { ZERO_ADDRESS } from './shared/constants'
import snapshotGasCost from './shared/snapshotGasCost'
import { collateralizeEthVault, getRewardsRootProof, updateRewards } from './shared/rewards'
import keccak256 from 'keccak256'

const createFixtureLoader = waffle.createFixtureLoader

describe('EthPrivErc20Vault', () => {
  const capacity = parseEther('1000')
  const name = 'SW ETH Vault'
  const symbol = 'SW-ETH-1'
  const feePercent = 1000
  const referrer = ZERO_ADDRESS
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  let dao: Wallet, sender: Wallet, admin: Wallet, other: Wallet
  let vault: EthPrivErc20Vault, keeper: Keeper, validatorsRegistry: Contract

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createPrivateVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthPrivErc20Vault']

  before('create fixture loader', async () => {
    ;[dao, sender, admin, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([dao])
  })

  beforeEach('deploy fixtures', async () => {
    ;({
      createEthPrivErc20Vault: createPrivateVault,
      keeper,
      validatorsRegistry,
    } = await loadFixture(ethVaultFixture))
    vault = await createPrivateVault(admin, {
      capacity,
      name,
      symbol,
      feePercent,
      metadataIpfsHash,
    })
  })

  it('has id', async () => {
    expect(await vault.vaultId()).to.eq(hexlify(keccak256('EthPrivErc20Vault')))
  })

  it('has version', async () => {
    expect(await vault.version()).to.eq(1)
  })

  describe('deposit', () => {
    const amount = parseEther('1')

    beforeEach(async () => {
      await vault.connect(admin).updateWhitelist(sender.address, true)
    })

    it('cannot be called by not whitelisted sender', async () => {
      await expect(
        vault.connect(other).deposit(other.address, referrer, { value: amount })
      ).to.revertedWith('AccessDenied')
    })

    it('cannot update state and call', async () => {
      await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
      const vaultReward = parseEther('1')
      const tree = await updateRewards(keeper, [
        { reward: vaultReward, unlockedMevReward: 0, vault: vault.address },
      ])

      const harvestParams: IKeeperRewards.HarvestParamsStruct = {
        rewardsRoot: tree.root,
        reward: vaultReward,
        unlockedMevReward: 0,
        proof: getRewardsRootProof(tree, {
          vault: vault.address,
          unlockedMevReward: 0,
          reward: vaultReward,
        }),
      }
      await expect(
        vault
          .connect(other)
          .updateStateAndDeposit(other.address, referrer, harvestParams, { value: amount })
      ).to.revertedWith('AccessDenied')
    })

    it('cannot set receiver to not whitelisted user', async () => {
      await expect(
        vault.connect(other).deposit(other.address, referrer, { value: amount })
      ).to.revertedWith('AccessDenied')
    })

    it('can be called by whitelisted user', async () => {
      const receipt = await vault
        .connect(sender)
        .deposit(sender.address, referrer, { value: amount })
      expect(await vault.balanceOf(sender.address)).to.eq(amount)

      await expect(receipt)
        .to.emit(vault, 'Deposited')
        .withArgs(sender.address, sender.address, amount, amount, referrer)
      await snapshotGasCost(receipt)
    })

    it('deposit through receive fallback cannot be called by not whitelisted sender', async () => {
      const depositorMockFactory = await ethers.getContractFactory('DepositorMock')
      const depositorMock = await depositorMockFactory.deploy(vault.address)

      const amount = parseEther('100')
      const expectedShares = parseEther('100')
      expect(await vault.convertToShares(amount)).to.eq(expectedShares)
      await expect(depositorMock.connect(sender).depositToVault({ value: amount })).to.revertedWith(
        'DepositFailed'
      )
    })

    it('deposit through receive fallback can be called by whitelisted sender', async () => {
      const depositorMockFactory = await ethers.getContractFactory('DepositorMock')
      const depositorMock = await depositorMockFactory.deploy(vault.address)
      await vault.connect(admin).updateWhitelist(depositorMock.address, true)

      const amount = parseEther('100')
      const expectedShares = parseEther('100')
      expect(await vault.convertToShares(amount)).to.eq(expectedShares)
      const receipt = await depositorMock.connect(sender).depositToVault({ value: amount })
      expect(await vault.balanceOf(depositorMock.address)).to.eq(expectedShares)

      await expect(receipt)
        .to.emit(vault, 'Deposited')
        .withArgs(
          depositorMock.address,
          depositorMock.address,
          amount,
          expectedShares,
          ZERO_ADDRESS
        )
      await snapshotGasCost(receipt)
    })
  })
})
