import { ethers } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { EthErc20Vault, Keeper } from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { createDepositorMock, ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { SECURITY_DEPOSIT, ZERO_ADDRESS } from './shared/constants'
import { collateralizeEthVault, getRewardsRootProof, updateRewards } from './shared/rewards'
import { setBalance } from './shared/utils'
import { registerEthValidator } from './shared/validators'
import keccak256 from 'keccak256'

const validatorDeposit = ethers.parseEther('32')

describe('EthErc20Vault', () => {
  const capacity = ethers.parseEther('1000')
  const name = 'SW ETH Vault'
  const symbol = 'SW-ETH-1'
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  const referrer = '0x' + '1'.repeat(40)
  let sender: Wallet, receiver: Wallet, admin: Wallet
  let vault: EthErc20Vault, keeper: Keeper, validatorsRegistry: Contract

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
    keeper = fixture.keeper
    validatorsRegistry = fixture.validatorsRegistry
  })

  it('has id', async () => {
    expect(await vault.vaultId()).to.eq('0x' + keccak256('EthErc20Vault').toString('hex'))
  })

  it('has version', async () => {
    expect(await vault.version()).to.eq(1)
  })

  it('deposit emits transfer event', async () => {
    const amount = ethers.parseEther('100')
    const expectedShares = ethers.parseEther('100')
    expect(await vault.convertToShares(amount)).to.eq(expectedShares)

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
    const expectedShares = ethers.parseEther('100')
    expect(await vault.convertToShares(amount)).to.eq(expectedShares)

    const receipt = await depositorMock.connect(sender).depositToVault({ value: amount })
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
    expect(await vault.queuedShares()).to.be.eq(0)

    const amount = ethers.parseEther('100')
    await vault.connect(sender).deposit(sender.address, referrer, { value: amount })
    expect(await vault.balanceOf(sender.address)).to.be.eq(amount)

    const receipt = await vault.connect(sender).enterExitQueue(amount, receiver.address)
    await expect(receipt)
      .to.emit(vault, 'ExitQueueEntered')
      .withArgs(sender.address, receiver.address, validatorDeposit, amount)
    await expect(receipt)
      .to.emit(vault, 'Transfer')
      .withArgs(sender.address, await vault.getAddress(), amount)
    expect(await vault.queuedShares()).to.be.eq(amount)
    expect(await vault.balanceOf(sender.address)).to.be.eq(0)

    await snapshotGasCost(receipt)
  })

  it('update exit queue emits transfer event', async () => {
    const validatorDeposit = ethers.parseEther('32')
    await vault.connect(admin).deposit(admin.address, ZERO_ADDRESS, { value: validatorDeposit })
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
    await vault.connect(admin).enterExitQueue(validatorDeposit, admin.address)
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

  it('cannot transfer vault shares when unharvested', async () => {
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
    const assets = ethers.parseEther('2')
    const osTokenShares = ethers.parseEther('1')

    await vault.connect(sender).deposit(sender.address, ZERO_ADDRESS, { value: assets })
    await vault.connect(sender).mintOsToken(receiver.address, osTokenShares, ZERO_ADDRESS)
    await updateRewards(keeper, [
      {
        vault: await vault.getAddress(),
        reward: ethers.parseEther('1'),
        unlockedMevReward: ethers.parseEther('0'),
      },
    ])
    await updateRewards(keeper, [
      {
        vault: await vault.getAddress(),
        reward: ethers.parseEther('1.2'),
        unlockedMevReward: ethers.parseEther('0'),
      },
    ])
    await expect(
      vault.connect(sender).transfer(receiver.address, assets)
    ).to.be.revertedWithCustomError(vault, 'NotHarvested')
  })

  it('cannot transfer vault shares when LTV is violated', async () => {
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
    const assets = ethers.parseEther('2')
    const osTokenShares = ethers.parseEther('1')

    await vault.connect(sender).deposit(sender.address, ZERO_ADDRESS, { value: assets })
    await vault.connect(sender).mintOsToken(receiver.address, osTokenShares, ZERO_ADDRESS)
    await expect(
      vault.connect(sender).transfer(receiver.address, assets)
    ).to.be.revertedWithCustomError(vault, 'LowLtv')
    await vault.connect(sender).approve(receiver.address, assets)
    await expect(
      vault.connect(receiver).transferFrom(sender.address, receiver.address, assets)
    ).to.be.revertedWithCustomError(vault, 'LowLtv')
  })
})
