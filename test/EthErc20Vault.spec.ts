import { ethers, waffle } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { hexlify, parseEther } from 'ethers/lib/utils'
import { EthErc20Vault, Keeper, OsToken } from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { SECURITY_DEPOSIT, ZERO_ADDRESS } from './shared/constants'
import { collateralizeEthVault, getRewardsRootProof, updateRewards } from './shared/rewards'
import { setBalance } from './shared/utils'
import { registerEthValidator } from './shared/validators'
import keccak256 from 'keccak256'

const createFixtureLoader = waffle.createFixtureLoader
const validatorDeposit = parseEther('32')

describe('EthErc20Vault', () => {
  const capacity = parseEther('1000')
  const name = 'SW ETH Vault'
  const symbol = 'SW-ETH-1'
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  const referrer = '0x' + '1'.repeat(40)
  let dao: Wallet, sender: Wallet, receiver: Wallet, admin: Wallet
  let vault: EthErc20Vault, keeper: Keeper, osToken: OsToken, validatorsRegistry: Contract

  let loadFixture: ReturnType<typeof createFixtureLoader>

  before('create fixture loader', async () => {
    ;[dao, sender, receiver, admin] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([dao])
  })

  beforeEach('deploy fixtures', async () => {
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
    osToken = fixture.osToken
  })

  it('has id', async () => {
    expect(await vault.vaultId()).to.eq(hexlify(keccak256('EthErc20Vault')))
  })

  it('has version', async () => {
    expect(await vault.version()).to.eq(1)
  })

  it('deposit emits transfer event', async () => {
    const amount = parseEther('100')
    const expectedShares = parseEther('100')
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
    const depositorMockFactory = await ethers.getContractFactory('DepositorMock')
    const depositorMock = await depositorMockFactory.deploy(vault.address)

    const amount = parseEther('100')
    const expectedShares = parseEther('100')
    expect(await vault.convertToShares(amount)).to.eq(expectedShares)

    const receipt = await depositorMock.connect(sender).depositToVault({ value: amount })
    expect(await vault.balanceOf(depositorMock.address)).to.eq(expectedShares)

    await expect(receipt)
      .to.emit(vault, 'Deposited')
      .withArgs(depositorMock.address, depositorMock.address, amount, expectedShares, ZERO_ADDRESS)
    await expect(receipt)
      .to.emit(vault, 'Transfer')
      .withArgs(ZERO_ADDRESS, depositorMock.address, expectedShares)
    await snapshotGasCost(receipt)
  })

  it('redeem emits transfer event', async () => {
    const amount = parseEther('100')
    await vault.connect(sender).deposit(sender.address, referrer, { value: amount })
    const receiverBalanceBefore = await waffle.provider.getBalance(receiver.address)
    const receipt = await vault.connect(sender).redeem(amount, receiver.address)
    await expect(receipt)
      .to.emit(vault, 'Redeemed')
      .withArgs(sender.address, receiver.address, amount, amount)
    await expect(receipt).to.emit(vault, 'Transfer').withArgs(sender.address, ZERO_ADDRESS, amount)

    expect(await vault.totalAssets()).to.be.eq(SECURITY_DEPOSIT)
    expect(await vault.totalSupply()).to.be.eq(SECURITY_DEPOSIT)
    expect(await vault.balanceOf(sender.address)).to.be.eq(0)
    expect(await waffle.provider.getBalance(vault.address)).to.be.eq(SECURITY_DEPOSIT)
    expect(await waffle.provider.getBalance(receiver.address)).to.be.eq(
      receiverBalanceBefore.add(amount)
    )

    await snapshotGasCost(receipt)
  })

  it('enter exit queue emits transfer event', async () => {
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
    expect(await vault.queuedShares()).to.be.eq(0)

    const amount = parseEther('100')
    await vault.connect(sender).deposit(sender.address, referrer, { value: amount })
    expect(await vault.balanceOf(sender.address)).to.be.eq(amount)

    const receipt = await vault.connect(sender).enterExitQueue(amount, receiver.address)
    await expect(receipt)
      .to.emit(vault, 'ExitQueueEntered')
      .withArgs(sender.address, receiver.address, validatorDeposit, amount)
    await expect(receipt).to.emit(vault, 'Transfer').withArgs(sender.address, vault.address, amount)
    expect(await vault.queuedShares()).to.be.eq(amount)
    expect(await vault.balanceOf(sender.address)).to.be.eq(0)

    await snapshotGasCost(receipt)
  })

  it('update exit queue emits transfer event', async () => {
    const validatorDeposit = parseEther('32')
    await vault.connect(admin).deposit(admin.address, ZERO_ADDRESS, { value: validatorDeposit })
    await registerEthValidator(vault, keeper, validatorsRegistry, admin)

    const rewardsTree = await updateRewards(keeper, [
      { vault: vault.address, reward: 0, unlockedMevReward: 0 },
    ])
    const proof = getRewardsRootProof(rewardsTree, {
      vault: vault.address,
      reward: 0,
      unlockedMevReward: 0,
    })

    // exit validator
    await vault.connect(admin).callStatic.enterExitQueue(validatorDeposit, admin.address)
    await vault.connect(admin).enterExitQueue(validatorDeposit, admin.address)
    await setBalance(vault.address, validatorDeposit)

    const receipt = await vault.updateState({
      rewardsRoot: rewardsTree.root,
      reward: 0,
      unlockedMevReward: 0,
      proof,
    })
    await expect(receipt)
      .to.emit(vault, 'Transfer')
      .withArgs(vault.address, ZERO_ADDRESS, validatorDeposit)

    await snapshotGasCost(receipt)
  })

  it('cannot transfer vault shares when unharvested', async () => {
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
    const assets = parseEther('2')
    const osTokenShares = parseEther('1')

    await vault.connect(sender).deposit(sender.address, ZERO_ADDRESS, { value: assets })
    await vault.connect(sender).mintOsToken(receiver.address, osTokenShares, ZERO_ADDRESS)
    await updateRewards(keeper, [
      { vault: vault.address, reward: parseEther('1'), unlockedMevReward: parseEther('0') },
    ])
    await updateRewards(keeper, [
      { vault: vault.address, reward: parseEther('1.2'), unlockedMevReward: parseEther('0') },
    ])
    await expect(vault.connect(sender).transfer(receiver.address, assets)).to.be.revertedWith(
      'NotHarvested'
    )
  })

  it('cannot transfer vault shares when LTV is violated', async () => {
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
    const assets = parseEther('2')
    const osTokenShares = parseEther('1')

    await vault.connect(sender).deposit(sender.address, ZERO_ADDRESS, { value: assets })
    await vault.connect(sender).mintOsToken(receiver.address, osTokenShares, ZERO_ADDRESS)
    await expect(vault.connect(sender).transfer(receiver.address, assets)).to.be.revertedWith(
      'LowLtv'
    )
    await vault.connect(sender).approve(receiver.address, assets)
    await expect(
      vault.connect(receiver).transferFrom(sender.address, receiver.address, assets)
    ).to.be.revertedWith('LowLtv')
  })
})
