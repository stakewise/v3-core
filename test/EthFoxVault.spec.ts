import { ethers } from 'hardhat'
import keccak256 from 'keccak256'
import { Contract, parseEther, Signer, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { Keeper, IKeeperRewards, EthFoxVault, DepositDataManager } from '../typechain-types'
import { ThenArg } from '../helpers/types'
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
import { extractDepositShares, extractExitPositionTicket } from './shared/utils'

describe('EthFoxVault', () => {
  const capacity = ethers.parseEther('1000')
  const feePercent = 1000
  const referrer = ZERO_ADDRESS
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  let sender: Wallet, blocklistManager: Wallet, admin: Signer, other: Wallet
  let vault: EthFoxVault,
    keeper: Keeper,
    validatorsRegistry: Contract,
    depositDataManager: DepositDataManager

  let createFoxVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthFoxVault']

  before('create fixture loader', async () => {
    ;[sender, blocklistManager, admin, other] = (await (ethers as any).getSigners()).slice(1, 5)
  })

  beforeEach('deploy fixtures', async () => {
    ;({
      createEthFoxVault: createFoxVault,
      keeper,
      validatorsRegistry,
      depositDataManager,
    } = await loadFixture(ethVaultFixture))
    vault = await createFoxVault(admin, {
      capacity,
      feePercent,
      metadataIpfsHash,
    })
    admin = await ethers.getImpersonatedSigner(await vault.admin())
  })

  it('cannot initialize twice', async () => {
    await expect(vault.connect(other).initialize('0x')).revertedWithCustomError(
      vault,
      'InvalidInitialization'
    )
  })

  it('has id', async () => {
    expect(await vault.vaultId()).to.eq(`0x${keccak256('EthFoxVault').toString('hex')}`)
  })

  it('has version', async () => {
    expect(await vault.version()).to.eq(2)
  })

  describe('set blocklist manager', () => {
    it('cannot be called by not admin', async () => {
      await expect(
        vault.connect(other).setBlocklistManager(blocklistManager.address)
      ).to.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('admin can update blocklist manager', async () => {
      const tx = await vault.connect(admin).setBlocklistManager(blocklistManager.address)
      await expect(tx)
        .to.emit(vault, 'BlocklistManagerUpdated')
        .withArgs(await admin.getAddress(), blocklistManager.address)
      expect(await vault.blocklistManager()).to.be.eq(blocklistManager.address)
      await snapshotGasCost(tx)
    })
  })

  describe('blocklist', () => {
    beforeEach(async () => {
      await vault.connect(admin).setBlocklistManager(blocklistManager.address)
    })

    it('cannot be updated by not blocklist manager', async () => {
      await expect(
        vault.connect(other).updateBlocklist(sender.address, true)
      ).to.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('cannot be updated twice', async () => {
      await vault.connect(blocklistManager).updateBlocklist(sender.address, true)
      await expect(
        vault.connect(blocklistManager).updateBlocklist(sender.address, true)
      ).to.not.emit(vault, 'BlocklistUpdated')
    })

    it('can be updated by blocklist manager', async () => {
      // add to blocklist
      let tx = await vault.connect(blocklistManager).updateBlocklist(sender.address, true)
      await expect(tx)
        .to.emit(vault, 'BlocklistUpdated')
        .withArgs(blocklistManager.address, sender.address, true)
      expect(await vault.blockedAccounts(sender.address)).to.be.eq(true)
      await snapshotGasCost(tx)

      // remove from blocklist
      tx = await vault.connect(blocklistManager).updateBlocklist(sender.address, false)
      await expect(tx)
        .to.emit(vault, 'BlocklistUpdated')
        .withArgs(blocklistManager.address, sender.address, false)
      expect(await vault.blockedAccounts(sender.address)).to.be.eq(false)
      await snapshotGasCost(tx)
    })
  })

  describe('deposit', () => {
    const amount = ethers.parseEther('1')

    beforeEach(async () => {
      await vault.connect(admin).updateBlocklist(sender.address, true)
    })

    it('cannot be called by blocked sender', async () => {
      await expect(
        vault.connect(sender).deposit(sender.address, referrer, { value: amount })
      ).to.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('cannot update state and call', async () => {
      await collateralizeEthVault(vault, keeper, depositDataManager, admin, validatorsRegistry)
      const vaultReward = getHarvestParams(await vault.getAddress(), ethers.parseEther('1'), 0n)
      const tree = await updateRewards(keeper, [vaultReward])

      const harvestParams: IKeeperRewards.HarvestParamsStruct = {
        rewardsRoot: tree.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof: getRewardsRootProof(tree, vaultReward),
      }
      await expect(
        vault
          .connect(sender)
          .updateStateAndDeposit(sender.address, referrer, harvestParams, { value: amount })
      ).to.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('cannot set receiver to blocked user', async () => {
      await expect(
        vault.connect(other).deposit(sender.address, referrer, { value: amount })
      ).to.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('can be called by not blocked user', async () => {
      const receipt = await vault.connect(other).deposit(other.address, referrer, { value: amount })
      const shares = await extractDepositShares(receipt)

      await expect(receipt)
        .to.emit(vault, 'Deposited')
        .withArgs(other.address, other.address, amount, shares, referrer)
      await snapshotGasCost(receipt)
    })

    it('deposit through receive fallback cannot be called by blocked sender', async () => {
      const depositorMock = await createDepositorMock(vault)
      await vault.connect(admin).updateBlocklist(await depositorMock.getAddress(), true)
      const amount = ethers.parseEther('100')
      const expectedShares = await vault.convertToShares(amount)
      expect(await vault.convertToShares(amount)).to.eq(expectedShares)
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

  describe('ejecting user', () => {
    const senderAssets = parseEther('1')
    let senderShares: bigint

    beforeEach(async () => {
      await vault.connect(admin).setBlocklistManager(blocklistManager.address)
      const tx = await vault
        .connect(sender)
        .deposit(sender.address, referrer, { value: senderAssets })
      senderShares = await extractDepositShares(tx)
    })

    it('fails for not blocklist manager', async () => {
      await expect(vault.connect(other).ejectUser(sender.address)).to.revertedWithCustomError(
        vault,
        'AccessDenied'
      )
    })

    it('does not fail for user with no vault shares', async () => {
      expect(await vault.getShares(other.address)).to.eq(0)

      const tx = await vault.connect(blocklistManager).ejectUser(other.address)
      await expect(tx)
        .to.emit(vault, 'BlocklistUpdated')
        .withArgs(blocklistManager.address, other.address, true)
      expect(await vault.blockedAccounts(other.address)).to.eq(true)
      await expect(tx).to.not.emit(vault, 'V2ExitQueueEntered')
      await snapshotGasCost(tx)
    })

    it('blocklist manager can eject all of the user assets for collateralized vault', async () => {
      await collateralizeEthVault(vault, keeper, depositDataManager, admin, validatorsRegistry)

      const tx = await vault.connect(blocklistManager).ejectUser(sender.address)
      const positionTicket = await extractExitPositionTicket(tx)
      await expect(tx)
        .to.emit(vault, 'BlocklistUpdated')
        .withArgs(blocklistManager.address, sender.address, true)
      expect(await vault.blockedAccounts(sender.address)).to.eq(true)
      await expect(tx)
        .to.emit(vault, 'V2ExitQueueEntered')
        .withArgs(sender.address, sender.address, positionTicket, senderAssets, senderShares)
      await expect(tx).to.emit(vault, 'UserEjected').withArgs(sender.address, senderShares)
      expect(await vault.getShares(sender.address)).to.eq(0)
      await snapshotGasCost(tx)
    })
  })
})
