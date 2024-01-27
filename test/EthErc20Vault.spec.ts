import { ethers } from 'hardhat'
import { Contract, Signer, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { EthErc20Vault, Keeper, OsTokenVaultController } from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { createDepositorMock, ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { SECURITY_DEPOSIT, ZERO_ADDRESS } from './shared/constants'
import {
  collateralizeEthVault,
  getHarvestParams,
  getRewardsRootProof,
  updateRewards,
} from './shared/rewards'
import keccak256 from 'keccak256'
import { extractExitPositionTicket, setBalance } from './shared/utils'
import { MAINNET_FORK } from '../helpers/constants'
import { ThenArg } from '../helpers/types'
import { registerEthValidator } from './shared/validators'

describe('EthErc20Vault', () => {
  const capacity = ethers.parseEther('1000')
  const name = 'SW ETH Vault'
  const symbol = 'SW-ETH-1'
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  const referrer = '0x' + '1'.repeat(40)
  let sender: Wallet, receiver: Wallet, admin: Signer
  let vault: EthErc20Vault,
    keeper: Keeper,
    validatorsRegistry: Contract,
    osTokenVaultController: OsTokenVaultController

  let createErc20Vault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthErc20Vault']

  beforeEach('deploy fixtures', async () => {
    ;[sender, receiver, admin] = (await (ethers as any).getSigners()).slice(1, 4)
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
    createErc20Vault = fixture.createEthErc20Vault
  })

  it('has id', async () => {
    expect(await vault.vaultId()).to.eq('0x' + keccak256('EthErc20Vault').toString('hex'))
  })

  it('has version', async () => {
    expect(await vault.version()).to.eq(1)
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

  it('redeem emits transfer event', async () => {
    const vault = await createErc20Vault(
      admin,
      {
        capacity,
        name,
        symbol,
        feePercent,
        metadataIpfsHash,
      },
      false,
      true
    )
    const amount = ethers.parseEther('100')
    await vault.connect(sender).deposit(sender.address, referrer, { value: amount })
    const receiverBalanceBefore = await ethers.provider.getBalance(receiver.address)
    const receipt = await vault.connect(sender).redeem(amount, receiver.address)
    await expect(receipt)
      .to.emit(vault, 'Redeemed')
      .withArgs(sender.address, receiver.address, amount, amount)
    await expect(receipt).to.emit(vault, 'Transfer').withArgs(sender.address, ZERO_ADDRESS, amount)

    expect(await vault.totalAssets()).to.be.eq(SECURITY_DEPOSIT)
    expect(await vault.totalSupply()).to.be.eq(SECURITY_DEPOSIT)
    expect(await vault.balanceOf(sender.address)).to.be.eq(0)
    expect(await ethers.provider.getBalance(await vault.getAddress())).to.be.eq(SECURITY_DEPOSIT)
    expect(await ethers.provider.getBalance(receiver.address)).to.be.eq(
      receiverBalanceBefore + amount
    )

    await snapshotGasCost(receipt)
  })

  it('enter exit queue emits transfer event', async () => {
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
    const queuedSharesBefore = await vault.queuedShares()
    const totalAssetsBefore = await vault.totalAssets()
    const totalSharesBefore = await vault.totalShares()

    const assets = ethers.parseEther('100')
    let shares = await vault.convertToShares(assets)
    await vault.connect(sender).deposit(sender.address, referrer, { value: assets })
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
    expect(await vault.totalAssets()).to.be.eq(totalAssetsBefore + assets)
    expect(await vault.totalSupply()).to.be.eq(totalSharesBefore + shares)
    expect(await vault.balanceOf(sender.address)).to.be.eq(0)

    await snapshotGasCost(receipt)
  })

  it('update exit queue emits transfer event', async () => {
    const validatorDeposit = ethers.parseEther('32')
    await vault
      .connect(admin)
      .deposit(await admin.getAddress(), ZERO_ADDRESS, { value: validatorDeposit })
    await registerEthValidator(vault, keeper, validatorsRegistry, admin)

    const rewardsTree = await updateRewards(keeper, [
      { vault: await vault.getAddress(), reward: 0n, unlockedMevReward: 0n },
    ])
    const proof = getRewardsRootProof(rewardsTree, {
      vault: await vault.getAddress(),
      reward: 0n,
      unlockedMevReward: 0n,
    })

    // exit validator
    await vault.connect(admin).enterExitQueue(validatorDeposit, await admin.getAddress())
    await setBalance(await vault.getAddress(), validatorDeposit)

    const receipt = await vault.updateState({
      rewardsRoot: rewardsTree.root,
      reward: 0n,
      unlockedMevReward: 0n,
      proof,
    })
    await expect(receipt)
      .to.emit(vault, 'Transfer')
      .withArgs(await vault.getAddress(), ZERO_ADDRESS, validatorDeposit)

    await snapshotGasCost(receipt)
  })

  it('cannot transfer vault shares when unharvested and osToken minted', async () => {
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
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
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
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
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
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
})
