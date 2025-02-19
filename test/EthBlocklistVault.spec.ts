import { ethers } from 'hardhat'
import { Contract, Signer, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  EthBlocklistVault,
  IKeeperRewards,
  Keeper,
  OsTokenVaultController,
  DepositDataRegistry,
} from '../typechain-types'
import { createDepositorMock, ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { ZERO_ADDRESS } from './shared/constants'
import snapshotGasCost from './shared/snapshotGasCost'
import {
  collateralizeEthVault,
  getHarvestParams,
  getRewardsRootProof,
  updateRewards,
} from './shared/rewards'
import keccak256 from 'keccak256'
import { extractDepositShares } from './shared/utils'

describe('EthBlocklistVault', () => {
  const capacity = ethers.parseEther('1000')
  const feePercent = 1000
  const referrer = ZERO_ADDRESS
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  let sender: Wallet, admin: Signer, other: Wallet, blocklistManager: Wallet
  let vault: EthBlocklistVault,
    keeper: Keeper,
    validatorsRegistry: Contract,
    osTokenVaultController: OsTokenVaultController,
    depositDataRegistry: DepositDataRegistry

  beforeEach('deploy fixtures', async () => {
    ;[sender, admin, other, blocklistManager] = await (ethers as any).getSigners()
    const fixture = await loadFixture(ethVaultFixture)
    vault = await fixture.createEthBlocklistVault(admin, {
      capacity,
      feePercent,
      metadataIpfsHash,
    })
    admin = await ethers.getImpersonatedSigner(await vault.admin())
    keeper = fixture.keeper
    validatorsRegistry = fixture.validatorsRegistry
    osTokenVaultController = fixture.osTokenVaultController
    depositDataRegistry = fixture.depositDataRegistry
  })

  it('has id', async () => {
    expect(await vault.vaultId()).to.eq(`0x${keccak256('EthBlocklistVault').toString('hex')}`)
  })

  it('has version', async () => {
    expect(await vault.version()).to.eq(4)
  })

  it('cannot initialize twice', async () => {
    await expect(vault.connect(other).initialize('0x')).revertedWithCustomError(
      vault,
      'InvalidInitialization'
    )
  })

  describe('deposit', () => {
    const assets = ethers.parseEther('1')

    beforeEach(async () => {
      await vault.connect(admin).setBlocklistManager(blocklistManager.address)
    })

    it('cannot be called by blocked sender', async () => {
      await vault.connect(blocklistManager).updateBlocklist(other.address, true)
      await expect(
        vault.connect(other).deposit(other.address, referrer, { value: assets })
      ).to.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('cannot update state and call by blocked sender', async () => {
      await collateralizeEthVault(vault, keeper, depositDataRegistry, admin, validatorsRegistry)
      const vaultReward = getHarvestParams(await vault.getAddress(), ethers.parseEther('1'), 0n)
      const tree = await updateRewards(keeper, [vaultReward])

      const harvestParams: IKeeperRewards.HarvestParamsStruct = {
        rewardsRoot: tree.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof: getRewardsRootProof(tree, vaultReward),
      }
      await vault.connect(blocklistManager).updateBlocklist(other.address, true)
      await expect(
        vault
          .connect(other)
          .updateStateAndDeposit(other.address, referrer, harvestParams, { value: assets })
      ).to.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('cannot set receiver to blocked user', async () => {
      await vault.connect(blocklistManager).updateBlocklist(other.address, true)
      await expect(
        vault.connect(sender).deposit(other.address, referrer, { value: assets })
      ).to.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('can be called by not blocked user', async () => {
      const receipt = await vault
        .connect(sender)
        .deposit(sender.address, referrer, { value: assets })
      const shares = await extractDepositShares(receipt)

      await expect(receipt)
        .to.emit(vault, 'Deposited')
        .withArgs(sender.address, sender.address, assets, shares, referrer)
      await snapshotGasCost(receipt)
    })

    it('deposit through receive fallback cannot be called by blocked sender', async () => {
      const depositorMock = await createDepositorMock(vault)
      const amount = ethers.parseEther('100')
      const expectedShares = await vault.convertToShares(amount)
      expect(await vault.convertToShares(amount)).to.eq(expectedShares)
      await vault.connect(blocklistManager).updateBlocklist(await depositorMock.getAddress(), true)
      await expect(
        depositorMock.connect(sender).depositToVault({ value: amount })
      ).to.revertedWithCustomError(depositorMock, 'DepositFailed')
    })

    it('deposit through receive fallback can be called by not blocked sender', async () => {
      const depositorMock = await createDepositorMock(vault)
      const depositorMockAddress = await depositorMock.getAddress()

      const amount = ethers.parseEther('100')
      const expectedShares = await vault.convertToShares(amount)
      expect(await vault.convertToShares(amount)).to.eq(expectedShares)
      const receipt = await depositorMock.connect(sender).depositToVault({ value: amount })
      expect(await vault.getShares(depositorMockAddress)).to.eq(expectedShares)

      await expect(receipt)
        .to.emit(vault, 'Deposited')
        .withArgs(depositorMockAddress, depositorMockAddress, amount, expectedShares, ZERO_ADDRESS)
      await snapshotGasCost(receipt)
    })
  })

  describe('mint osToken', () => {
    const assets = ethers.parseEther('1')
    let osTokenShares: bigint

    beforeEach(async () => {
      await collateralizeEthVault(vault, keeper, depositDataRegistry, admin, validatorsRegistry)
      await vault.connect(sender).deposit(sender.address, referrer, { value: assets })
      osTokenShares = await osTokenVaultController.convertToShares(assets / 2n)
    })

    it('cannot mint from blocked user', async () => {
      await vault.connect(admin).updateBlocklist(sender.address, true)
      await expect(
        vault.connect(sender).mintOsToken(sender.address, osTokenShares, ZERO_ADDRESS)
      ).to.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('can mint from not blocked user', async () => {
      const tx = await vault
        .connect(sender)
        .mintOsToken(sender.address, osTokenShares, ZERO_ADDRESS)
      await expect(tx).to.emit(vault, 'OsTokenMinted')
      await snapshotGasCost(tx)
    })
  })
})
