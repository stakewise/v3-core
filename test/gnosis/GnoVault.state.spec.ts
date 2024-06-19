import { ethers } from 'hardhat'
import { Contract, parseEther, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  BalancerVaultMock,
  DepositDataRegistry,
  ERC20Mock,
  GnoOwnMevEscrow,
  GnoOwnMevEscrow__factory,
  GnoSharedMevEscrow,
  GnoVault,
  Keeper,
} from '../../typechain-types'
import { collateralizeGnoVault, gnoVaultFixture } from '../shared/gnoFixtures'
import { expect } from '../shared/expect'
import { ThenArg } from '../../helpers/types'
import { getHarvestParams, getRewardsRootProof, updateRewards } from '../shared/rewards'
import { setBalance } from '../shared/utils'
import snapshotGasCost from '../shared/snapshotGasCost'
import { ONE_DAY } from '../shared/constants'

describe('GnoVault', () => {
  const vaultParams = {
    capacity: ethers.parseEther('1000'),
    feePercent: 1000,
    metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u',
  }
  let admin: Wallet
  let gnoToken: ERC20Mock,
    balancerVault: BalancerVaultMock,
    sharedMevEscrow: GnoSharedMevEscrow,
    keeper: Keeper,
    validatorsRegistry: Contract,
    depositDataRegistry: DepositDataRegistry
  let xdaiGnoRate: bigint

  let createVault: ThenArg<ReturnType<typeof gnoVaultFixture>>['createGnoVault']

  beforeEach('deploy fixtures', async () => {
    ;[admin] = (await (ethers as any).getSigners()).slice(1, 2)
    const fixture = await loadFixture(gnoVaultFixture)
    gnoToken = fixture.gnoToken
    balancerVault = fixture.balancerVault
    keeper = fixture.keeper
    validatorsRegistry = fixture.validatorsRegistry
    sharedMevEscrow = fixture.sharedMevEscrow
    depositDataRegistry = fixture.depositDataRegistry
    createVault = fixture.createGnoVault
    await fixture.xdaiExchange.setStalePriceTimeDelta(ONE_DAY * 10)
  })

  describe('Shared MEV Escrow', () => {
    let vault: GnoVault

    beforeEach('deploy vault', async () => {
      vault = await createVault(admin, vaultParams, false)
      await collateralizeGnoVault(
        vault,
        gnoToken,
        keeper,
        depositDataRegistry,
        admin,
        validatorsRegistry
      )
      xdaiGnoRate = await balancerVault.xdaiGnoRate()
    })

    it('does not include MEV rewards in total assets delta', async () => {
      const vaultAddr = await vault.getAddress()
      const consensusReward = parseEther('0.001')
      const executionReward = parseEther('0.002')
      const vaultReward = getHarvestParams(
        await vault.getAddress(),
        consensusReward,
        executionReward
      )
      const rewardsTree = await updateRewards(keeper, [vaultReward])
      const proof = getRewardsRootProof(rewardsTree, vaultReward)
      await setBalance(await sharedMevEscrow.getAddress(), executionReward)

      const totalAssetsBefore = await vault.totalAssets()
      expect(await ethers.provider.getBalance(vaultAddr)).to.eq(0n)
      const receipt = await vault.updateState({
        rewardsRoot: rewardsTree.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof,
      })
      expect(await vault.totalAssets()).to.eq(totalAssetsBefore + consensusReward)
      expect(await ethers.provider.getBalance(vaultAddr)).to.eq(executionReward)
      expect(receipt).to.emit(sharedMevEscrow, 'Harvested').withArgs(vaultAddr, executionReward)
      await snapshotGasCost(receipt)

      const swappedGno = (executionReward * xdaiGnoRate) / parseEther('1')
      await gnoToken.mint(await balancerVault.getAddress(), swappedGno)

      await vault.swapXdaiToGno()
      expect(await ethers.provider.getBalance(vaultAddr)).to.eq(0n)
      expect(await vault.totalAssets()).to.eq(totalAssetsBefore + consensusReward + swappedGno)
    })
  })

  describe('Own MEV Escrow', () => {
    let vault: GnoVault
    let mevEscrow: GnoOwnMevEscrow

    beforeEach('deploy vault', async () => {
      vault = await createVault(admin, vaultParams, true)
      const mevEscrowAddr = await vault.mevEscrow()
      mevEscrow = GnoOwnMevEscrow__factory.connect(mevEscrowAddr, admin)
      await collateralizeGnoVault(
        vault,
        gnoToken,
        keeper,
        depositDataRegistry,
        admin,
        validatorsRegistry
      )
      xdaiGnoRate = await balancerVault.xdaiGnoRate()
    })

    it('does not include MEV rewards in total assets delta', async () => {
      const vaultAddr = await vault.getAddress()
      const consensusReward = parseEther('0.001')
      const executionReward = parseEther('0.002')
      const vaultReward = getHarvestParams(await vault.getAddress(), consensusReward, 0n)
      const rewardsTree = await updateRewards(keeper, [vaultReward])
      const proof = getRewardsRootProof(rewardsTree, vaultReward)
      await setBalance(await mevEscrow.getAddress(), executionReward)

      const totalAssetsBefore = await vault.totalAssets()
      expect(await ethers.provider.getBalance(vaultAddr)).to.eq(0n)
      const receipt = await vault.updateState({
        rewardsRoot: rewardsTree.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof,
      })
      expect(await vault.totalAssets()).to.eq(totalAssetsBefore + consensusReward)
      expect(await ethers.provider.getBalance(vaultAddr)).to.eq(executionReward)

      expect(receipt).to.emit(mevEscrow, 'Harvested').withArgs(vaultAddr, executionReward)
      await snapshotGasCost(receipt)

      const swappedGno = (executionReward * xdaiGnoRate) / parseEther('1')
      await gnoToken.mint(await balancerVault.getAddress(), swappedGno)

      await vault.swapXdaiToGno()
      expect(await ethers.provider.getBalance(vaultAddr)).to.eq(0n)
      expect(await vault.totalAssets()).to.eq(totalAssetsBefore + consensusReward + swappedGno)
    })
  })
})
