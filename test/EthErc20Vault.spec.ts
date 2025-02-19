import { ethers } from 'hardhat'
import { Contract, Signer, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  DepositDataRegistry,
  EthErc20Vault,
  IKeeperRewards,
  Keeper,
  OsToken,
  OsTokenConfig,
  OsTokenVaultController,
} from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { createDepositorMock, ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { MAX_UINT256, ZERO_ADDRESS } from './shared/constants'
import {
  collateralizeEthVault,
  getHarvestParams,
  getRewardsRootProof,
  setAvgRewardPerSecond,
  updateRewards,
} from './shared/rewards'
import keccak256 from 'keccak256'
import { extractExitPositionTicket, setBalance } from './shared/utils'
import { MAINNET_FORK } from '../helpers/constants'
import { registerEthValidator } from './shared/validators'

describe('EthErc20Vault', () => {
  const capacity = ethers.parseEther('1000')
  const name = 'SW ETH Vault'
  const symbol = 'SW-ETH-1'
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  const referrer = '0x' + '1'.repeat(40)
  let sender: Wallet, receiver: Wallet, admin: Signer, dao: Wallet, other: Wallet
  let vault: EthErc20Vault,
    keeper: Keeper,
    validatorsRegistry: Contract,
    osTokenVaultController: OsTokenVaultController,
    osTokenConfig: OsTokenConfig,
    depositDataRegistry: DepositDataRegistry,
    osToken: OsToken

  beforeEach('deploy fixtures', async () => {
    ;[dao, sender, receiver, admin, other] = await (ethers as any).getSigners()
    const fixture = await loadFixture(ethVaultFixture)
    vault = await fixture.createEthErc20Vault(admin, {
      capacity,
      name,
      symbol,
      feePercent,
      metadataIpfsHash,
    })
    admin = await ethers.getImpersonatedSigner(await vault.admin())
    keeper = fixture.keeper
    validatorsRegistry = fixture.validatorsRegistry
    osTokenVaultController = fixture.osTokenVaultController
    osTokenConfig = fixture.osTokenConfig
    depositDataRegistry = fixture.depositDataRegistry
    osToken = fixture.osToken
  })

  it('has id', async () => {
    expect(await vault.vaultId()).to.eq('0x' + keccak256('EthErc20Vault').toString('hex'))
  })

  it('has version', async () => {
    expect(await vault.version()).to.eq(4)
  })

  it('deposit emits transfer event', async () => {
    const amount = ethers.parseEther('100')
    let expectedShares = await vault.convertToShares(amount)
    if (MAINNET_FORK.enabled) {
      expectedShares += 1n // rounding error
    }

    const receipt = await vault
      .connect(sender)
      .deposit(receiver.address, referrer, { value: amount })
    expect(await vault.balanceOf(receiver.address)).to.eq(expectedShares)

    await expect(receipt)
      .to.emit(vault, 'Deposited')
      .withArgs(sender.address, receiver.address, amount, expectedShares, referrer)
    await expect(receipt)
      .to.emit(vault, 'Transfer')
      .withArgs(ZERO_ADDRESS, receiver.address, expectedShares)
    await snapshotGasCost(receipt)
  })

  it('deposit through receive fallback function emits transfer event', async () => {
    const depositorMock = await createDepositorMock(vault)
    const depositorMockAddress = await depositorMock.getAddress()

    const amount = ethers.parseEther('100')
    let expectedShares = await vault.convertToShares(amount)
    expect(await vault.convertToShares(amount)).to.eq(expectedShares)

    const receipt = await depositorMock.connect(sender).depositToVault({ value: amount })
    if (MAINNET_FORK.enabled) {
      expectedShares += 1n // rounding error
    }
    expect(await vault.balanceOf(depositorMockAddress)).to.eq(expectedShares)

    await expect(receipt)
      .to.emit(vault, 'Deposited')
      .withArgs(depositorMockAddress, depositorMockAddress, amount, expectedShares, ZERO_ADDRESS)
    await expect(receipt)
      .to.emit(vault, 'Transfer')
      .withArgs(ZERO_ADDRESS, depositorMockAddress, expectedShares)
    await snapshotGasCost(receipt)
  })

  it('enter exit queue emits transfer event', async () => {
    await collateralizeEthVault(vault, keeper, depositDataRegistry, admin, validatorsRegistry)
    const queuedSharesBefore = await vault.queuedShares()
    const totalAssetsBefore = await vault.totalAssets()
    const totalSharesBefore = await vault.totalShares()

    const amount = ethers.parseEther('100')
    let shares = await vault.convertToShares(amount)
    await vault.connect(sender).deposit(sender.address, referrer, { value: amount })
    if (MAINNET_FORK.enabled) {
      shares += 1n // rounding error
    }
    expect(await vault.balanceOf(sender.address)).to.be.eq(shares)

    const receipt = await vault.connect(sender).enterExitQueue(shares, receiver.address)
    const positionTicket = await extractExitPositionTicket(receipt)
    await expect(receipt)
      .to.emit(vault, 'ExitQueueEntered')
      .withArgs(sender.address, receiver.address, positionTicket, shares)
    await expect(receipt)
      .to.emit(vault, 'Transfer')
      .withArgs(sender.address, await vault.getAddress(), shares)
    expect(await vault.queuedShares()).to.be.eq(queuedSharesBefore + shares)
    expect(await vault.totalAssets()).to.be.eq(totalAssetsBefore + amount)
    expect(await vault.totalSupply()).to.be.eq(totalSharesBefore + shares)
    expect(await vault.balanceOf(sender.address)).to.be.eq(0)

    await snapshotGasCost(receipt)
  })

  it('update exit queue emits transfer event', async () => {
    const validatorDeposit = ethers.parseEther('32')
    await vault.connect(sender).deposit(sender.address, ZERO_ADDRESS, { value: validatorDeposit })
    await registerEthValidator(vault, keeper, depositDataRegistry, admin, validatorsRegistry)

    const vaultReward = getHarvestParams(await vault.getAddress(), 0n, 0n)
    const rewardsTree = await updateRewards(keeper, [vaultReward])
    const proof = getRewardsRootProof(rewardsTree, {
      vault: await vault.getAddress(),
      reward: vaultReward.reward,
      unlockedMevReward: vaultReward.unlockedMevReward,
    })

    // exit validator
    let shares = await vault.convertToShares(validatorDeposit)
    await vault.connect(sender).enterExitQueue(shares, sender.address)
    await setBalance(await vault.getAddress(), validatorDeposit)

    const receipt = await vault.updateState({
      rewardsRoot: rewardsTree.root,
      reward: vaultReward.reward,
      unlockedMevReward: vaultReward.unlockedMevReward,
      proof,
    })

    if (MAINNET_FORK.enabled) {
      shares -= 1n // rounding error
    }

    await expect(receipt)
      .to.emit(vault, 'Transfer')
      .withArgs(await vault.getAddress(), ZERO_ADDRESS, shares)

    await snapshotGasCost(receipt)
  })

  it('cannot transfer vault shares when unharvested and osToken minted', async () => {
    await collateralizeEthVault(vault, keeper, depositDataRegistry, admin, validatorsRegistry)
    const assets = ethers.parseEther('1')
    const shares = await vault.convertToShares(assets)
    const osTokenShares = await osTokenVaultController.convertToShares(assets / 2n)

    await vault.connect(sender).deposit(sender.address, ZERO_ADDRESS, { value: assets })
    await vault.connect(sender).mintOsToken(receiver.address, osTokenShares, ZERO_ADDRESS)

    await updateRewards(keeper, [
      getHarvestParams(await vault.getAddress(), ethers.parseEther('1'), ethers.parseEther('0')),
    ])
    await updateRewards(keeper, [
      getHarvestParams(await vault.getAddress(), ethers.parseEther('1.2'), ethers.parseEther('0')),
    ])
    await expect(
      vault.connect(sender).transfer(receiver.address, shares)
    ).to.be.revertedWithCustomError(vault, 'NotHarvested')
  })

  it('cannot transfer vault shares when LTV is violated', async () => {
    await collateralizeEthVault(vault, keeper, depositDataRegistry, admin, validatorsRegistry)
    const assets = ethers.parseEther('2')
    const shares = await vault.convertToShares(assets)
    const osTokenShares = await osTokenVaultController.convertToShares(assets / 2n)

    await vault.connect(sender).deposit(sender.address, ZERO_ADDRESS, { value: assets })
    await vault.connect(sender).mintOsToken(receiver.address, osTokenShares, ZERO_ADDRESS)
    await expect(
      vault.connect(sender).transfer(receiver.address, shares)
    ).to.be.revertedWithCustomError(vault, 'LowLtv')
    await vault.connect(sender).approve(receiver.address, shares)
    await expect(
      vault.connect(receiver).transferFrom(sender.address, receiver.address, shares)
    ).to.be.revertedWithCustomError(vault, 'LowLtv')
  })

  it('can transfer vault shares when LTV is not violated', async () => {
    await collateralizeEthVault(vault, keeper, depositDataRegistry, admin, validatorsRegistry)
    const assets = ethers.parseEther('2')
    const osTokenShares = await osTokenVaultController.convertToShares(assets / 2n)
    const transferShares = await vault.convertToShares(ethers.parseEther('0.1'))

    await vault.connect(sender).deposit(sender.address, ZERO_ADDRESS, { value: assets })
    await vault.connect(sender).mintOsToken(receiver.address, osTokenShares, ZERO_ADDRESS)
    await expect(vault.connect(sender).transfer(receiver.address, transferShares)).to.emit(
      vault,
      'Transfer'
    )
    await vault.connect(sender).approve(receiver.address, transferShares)
    await expect(
      vault.connect(receiver).transferFrom(sender.address, receiver.address, transferShares)
    ).to.emit(vault, 'Transfer')
  })

  it('can deposit and mint osToken in one transaction', async () => {
    const assets = ethers.parseEther('1')
    let shares = await vault.convertToShares(assets)

    await setAvgRewardPerSecond(dao, vault, keeper, 0)
    expect(await vault.osTokenPositions(sender.address)).to.eq(0n)
    expect(await vault.getShares(sender.address)).to.eq(0n)

    // max shares
    const config = await osTokenConfig.getConfig(await vault.getAddress())
    let osTokenAssets = (assets * config.ltvPercent) / ethers.parseEther('1')
    let osTokenShares = await osTokenVaultController.convertToShares(osTokenAssets)
    let receipt = await vault
      .connect(sender)
      .depositAndMintOsToken(receiver.address, MAX_UINT256, ZERO_ADDRESS, { value: assets })

    if (MAINNET_FORK.enabled) {
      shares += 1n // rounding error
      osTokenAssets -= 1n // rounding error
    }

    expect(await osToken.balanceOf(receiver.address)).to.eq(osTokenShares)
    expect(await vault.osTokenPositions(sender.address)).to.eq(osTokenShares)
    expect(await vault.getShares(sender.address)).to.eq(shares)
    await expect(receipt)
      .to.emit(vault, 'Deposited')
      .withArgs(sender.address, sender.address, assets, shares, ZERO_ADDRESS)
    await expect(receipt).to.emit(vault, 'Transfer').withArgs(ZERO_ADDRESS, sender.address, shares)
    await expect(receipt)
      .to.emit(vault, 'OsTokenMinted')
      .withArgs(sender.address, receiver.address, osTokenAssets, osTokenShares, ZERO_ADDRESS)
    await snapshotGasCost(receipt)

    // mint osToken with half shares
    osTokenAssets = assets / 2n
    osTokenShares = await osTokenVaultController.convertToShares(osTokenAssets)
    receipt = await vault
      .connect(receiver)
      .depositAndMintOsToken(other.address, osTokenShares, ZERO_ADDRESS, { value: assets })

    if (MAINNET_FORK.enabled) {
      osTokenAssets -= 1n // rounding error
    }

    expect(await osToken.balanceOf(other.address)).to.eq(osTokenShares)
    expect(await vault.osTokenPositions(receiver.address)).to.eq(osTokenShares)
    expect(await vault.getShares(receiver.address)).to.eq(shares)
    await expect(receipt)
      .to.emit(vault, 'Deposited')
      .withArgs(receiver.address, receiver.address, assets, shares, ZERO_ADDRESS)
    await expect(receipt)
      .to.emit(vault, 'Transfer')
      .withArgs(ZERO_ADDRESS, receiver.address, shares)
    await expect(receipt)
      .to.emit(vault, 'OsTokenMinted')
      .withArgs(receiver.address, other.address, osTokenAssets, osTokenShares, ZERO_ADDRESS)
    await snapshotGasCost(receipt)
  })

  it('can update state, deposit, and mint osToken in one transaction', async () => {
    await setAvgRewardPerSecond(dao, vault, keeper, 0)
    const vaultAddr = await vault.getAddress()
    const assets = ethers.parseEther('1')
    const vaultReward = getHarvestParams(vaultAddr, 0n, 0n)
    await updateRewards(keeper, [vaultReward], 0)
    const tree = await updateRewards(keeper, [vaultReward], 0)
    const harvestParams: IKeeperRewards.HarvestParamsStruct = {
      rewardsRoot: tree.root,
      reward: vaultReward.reward,
      unlockedMevReward: vaultReward.unlockedMevReward,
      proof: getRewardsRootProof(tree, vaultReward),
    }

    expect(await vault.osTokenPositions(sender.address)).to.eq(0n)
    expect(await vault.getShares(sender.address)).to.eq(0n)

    const config = await osTokenConfig.getConfig(await vault.getAddress())
    let osTokenAssets = (assets * config.ltvPercent) / ethers.parseEther('1')
    const osTokenShares = await osTokenVaultController.convertToShares(osTokenAssets)
    const receipt = await vault
      .connect(sender)
      .updateStateAndDepositAndMintOsToken(
        receiver.address,
        MAX_UINT256,
        ZERO_ADDRESS,
        harvestParams,
        {
          value: assets,
        }
      )

    let shares = await vault.convertToShares(assets)
    if (MAINNET_FORK.enabled) {
      shares += 1n // rounding error
      osTokenAssets -= 1n // rounding error
    }

    expect(await osToken.balanceOf(receiver.address)).to.eq(osTokenShares)
    expect(await vault.osTokenPositions(sender.address)).to.eq(osTokenShares)
    expect(await vault.getShares(sender.address)).to.eq(shares)
    await expect(receipt)
      .to.emit(vault, 'Deposited')
      .withArgs(sender.address, sender.address, assets, shares, ZERO_ADDRESS)
    await expect(receipt).to.emit(vault, 'Transfer').withArgs(ZERO_ADDRESS, sender.address, shares)
    await expect(receipt)
      .to.emit(vault, 'OsTokenMinted')
      .withArgs(sender.address, receiver.address, osTokenAssets, osTokenShares, ZERO_ADDRESS)
    await snapshotGasCost(receipt)
  })
})
