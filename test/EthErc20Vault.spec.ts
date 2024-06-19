import { ethers } from 'hardhat'
import { Contract, Signer, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  EthErc20Vault,
  Keeper,
  OsTokenVaultController,
  VaultsRegistry,
  OsTokenConfig,
  SharedMevEscrow,
  DepositDataRegistry,
} from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import {
  createDepositorMock,
  deployEthVaultV1,
  encodeEthErc20VaultInitParams,
  ethVaultFixture,
} from './shared/fixtures'
import { expect } from './shared/expect'
import { ZERO_ADDRESS } from './shared/constants'
import {
  collateralizeEthVault,
  getHarvestParams,
  getRewardsRootProof,
  updateRewards,
} from './shared/rewards'
import keccak256 from 'keccak256'
import { extractExitPositionTicket, setBalance } from './shared/utils'
import { MAINNET_FORK } from '../helpers/constants'
import { registerEthValidator } from './shared/validators'
import { getEthErc20VaultV1Factory } from './shared/contracts'

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
    osTokenVaultController: OsTokenVaultController,
    vaultsRegistry: VaultsRegistry,
    osTokenConfig: OsTokenConfig,
    sharedMevEscrow: SharedMevEscrow,
    depositDataRegistry: DepositDataRegistry

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
    osTokenConfig = fixture.osTokenConfig
    vaultsRegistry = fixture.vaultsRegistry
    sharedMevEscrow = fixture.sharedMevEscrow
    depositDataRegistry = fixture.depositDataRegistry
  })

  it('has id', async () => {
    expect(await vault.vaultId()).to.eq('0x' + keccak256('EthErc20Vault').toString('hex'))
  })

  it('has version', async () => {
    expect(await vault.version()).to.eq(2)
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
    expect(await vault.totalExitingAssets()).to.be.eq(0)
    const totalExitingBefore = await vault.totalExitingAssets()
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
      .to.emit(vault, 'V2ExitQueueEntered')
      .withArgs(sender.address, receiver.address, positionTicket, shares, amount)
    await expect(receipt).to.emit(vault, 'Transfer').withArgs(sender.address, ZERO_ADDRESS, shares)
    expect(await vault.totalExitingAssets()).to.be.eq(totalExitingBefore + amount)
    expect(await vault.totalAssets()).to.be.eq(totalAssetsBefore)
    expect(await vault.totalSupply()).to.be.eq(totalSharesBefore)
    expect(await vault.balanceOf(sender.address)).to.be.eq(0)

    await snapshotGasCost(receipt)
  })

  it('update exit queue emits transfer event', async () => {
    const vault = await deployEthVaultV1(
      await getEthErc20VaultV1Factory(),
      admin,
      keeper,
      vaultsRegistry,
      validatorsRegistry,
      osTokenVaultController,
      osTokenConfig,
      sharedMevEscrow,
      encodeEthErc20VaultInitParams({
        capacity,
        name,
        symbol,
        feePercent,
        metadataIpfsHash,
      })
    )
    const validatorDeposit = ethers.parseEther('32')
    await vault
      .connect(admin)
      .deposit(await admin.getAddress(), ZERO_ADDRESS, { value: validatorDeposit })
    await registerEthValidator(vault, keeper, depositDataRegistry, admin, validatorsRegistry)

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
})
