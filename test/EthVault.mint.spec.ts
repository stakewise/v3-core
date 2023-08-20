import { ethers, waffle } from 'hardhat'
import { BigNumber, Contract, Wallet } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import { EthVault, Keeper, OsToken, UnknownVaultMock, VaultsRegistry } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import snapshotGasCost from './shared/snapshotGasCost'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { ONE_DAY, ZERO_ADDRESS } from './shared/constants'
import { collateralizeEthVault, updateRewards } from './shared/rewards'
import { increaseTime } from './shared/utils'

const createFixtureLoader = waffle.createFixtureLoader

describe('EthVault - mint', () => {
  const assets = parseEther('2')
  const osTokenShares = parseEther('1')
  const vaultParams = {
    capacity: parseEther('1000'),
    feePercent: 1000,
    metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u',
  }
  let sender: Wallet, receiver: Wallet, admin: Wallet, owner: Wallet
  let vault: EthVault,
    keeper: Keeper,
    vaultsRegistry: VaultsRegistry,
    osToken: OsToken,
    validatorsRegistry: Contract

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVault']

  before('create fixture loader', async () => {
    ;[sender, receiver, owner, admin] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([owner])
  })

  beforeEach('deploy fixture', async () => {
    ;({
      createEthVault: createVault,
      keeper,
      validatorsRegistry,
      osToken,
      vaultsRegistry,
    } = await loadFixture(ethVaultFixture))
    vault = await createVault(admin, vaultParams)
    await osToken.connect(owner).setVaultImplementation(await vault.implementation(), true)

    // collateralize vault
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
    await vault.connect(sender).deposit(sender.address, ZERO_ADDRESS, { value: assets })
  })

  it('cannot mint osTokens from not collateralized vault', async () => {
    const notCollatVault = await createVault(admin, vaultParams, false)
    await expect(
      notCollatVault.connect(sender).mintOsToken(receiver.address, osTokenShares, ZERO_ADDRESS)
    ).to.be.revertedWith('NotCollateralized')
  })

  it('cannot mint osTokens from not harvested vault', async () => {
    await updateRewards(keeper, [
      { vault: vault.address, reward: parseEther('1'), unlockedMevReward: parseEther('0') },
    ])
    await updateRewards(keeper, [
      { vault: vault.address, reward: parseEther('1.2'), unlockedMevReward: parseEther('0') },
    ])
    await expect(
      vault.connect(sender).mintOsToken(receiver.address, osTokenShares, ZERO_ADDRESS)
    ).to.be.revertedWith('NotHarvested')
  })

  it('cannot mint osTokens to zero address', async () => {
    await expect(
      vault.connect(sender).mintOsToken(ZERO_ADDRESS, osTokenShares, ZERO_ADDRESS)
    ).to.be.revertedWith('ZeroAddress')
  })

  it('cannot mint zero osToken shares', async () => {
    await expect(
      vault.connect(sender).mintOsToken(receiver.address, 0, ZERO_ADDRESS)
    ).to.be.revertedWith('InvalidShares')
  })

  it('cannot mint osTokens from unregistered vault', async () => {
    const factory = await ethers.getContractFactory('UnknownVaultMock')
    const unknownVault = (await factory.deploy(
      osToken.address,
      await vault.implementation()
    )) as UnknownVaultMock
    await expect(
      unknownVault.connect(sender).mintOsToken(receiver.address, osTokenShares)
    ).to.be.revertedWith('AccessDenied')
  })

  it('cannot mint osTokens from vault with unsupported implementation', async () => {
    const factory = await ethers.getContractFactory('UnknownVaultMock')
    const unknownVault = (await factory.deploy(osToken.address, ZERO_ADDRESS)) as UnknownVaultMock
    await vaultsRegistry.connect(owner).addVault(unknownVault.address)
    await expect(
      unknownVault.connect(sender).mintOsToken(receiver.address, osTokenShares)
    ).to.be.revertedWith('AccessDenied')
  })

  it('cannot mint osTokens when it exceeds capacity', async () => {
    const osTokenAssets = await vault.convertToAssets(osTokenShares)
    await osToken.connect(owner).setCapacity(osTokenAssets.sub(1))
    await expect(
      vault.connect(sender).mintOsToken(receiver.address, osTokenShares, ZERO_ADDRESS)
    ).to.be.revertedWith('CapacityExceeded')
  })

  it('cannot mint osTokens when LTV is violated', async () => {
    const shares = await vault.convertToAssets(assets)
    await expect(
      vault.connect(sender).mintOsToken(receiver.address, shares, ZERO_ADDRESS)
    ).to.be.revertedWith('LowLtv')
  })

  it('cannot enter exit queue when LTV is violated', async () => {
    await vault.connect(sender).mintOsToken(receiver.address, osTokenShares, ZERO_ADDRESS)
    await expect(vault.connect(sender).enterExitQueue(assets, receiver.address)).to.be.revertedWith(
      'LowLtv'
    )
  })

  it('cannot redeem when LTV is violated', async () => {
    await vault.connect(sender).mintOsToken(receiver.address, osTokenShares, ZERO_ADDRESS)
    await expect(vault.connect(sender).redeem(assets, receiver.address)).to.be.revertedWith(
      'LowLtv'
    )
  })

  it('updates position accumulated fee', async () => {
    const treasury = await osToken.treasury()
    let totalShares = osTokenShares
    let totalAssets = await vault.convertToAssets(osTokenShares)
    let cumulativeFeePerShare = parseEther('1')
    let treasuryShares = BigNumber.from(0)
    let positionShares = osTokenShares
    let receiverShares = osTokenShares

    expect(await osToken.cumulativeFeePerShare()).to.eq(cumulativeFeePerShare)
    expect(await vault.osTokenPositions(sender.address)).to.eq(0)

    const verify = async () => {
      expect(await osToken.totalSupply()).to.eq(totalShares)
      expect(await osToken.totalAssets()).to.eq(totalAssets)
      expect(await osToken.cumulativeFeePerShare()).to.eq(cumulativeFeePerShare)
      expect(await osToken.balanceOf(treasury)).to.eq(treasuryShares)
      expect(await osToken.balanceOf(sender.address)).to.eq(0)
      expect(await vault.osTokenPositions(sender.address)).to.eq(positionShares)
      expect(await osToken.balanceOf(receiver.address)).to.eq(receiverShares)
    }

    let receipt = await vault
      .connect(sender)
      .mintOsToken(receiver.address, osTokenShares, ZERO_ADDRESS)
    await verify()

    await snapshotGasCost(receipt)
    await increaseTime(ONE_DAY)

    expect(await osToken.cumulativeFeePerShare()).to.be.above(cumulativeFeePerShare)
    expect(await osToken.totalAssets()).to.be.above(totalAssets)
    expect(await osToken.convertToAssets(receiverShares)).to.be.above(osTokenShares)
    expect(await vault.osTokenPositions(sender.address)).to.be.above(positionShares)

    receipt = await vault.connect(sender).mintOsToken(receiver.address, 100, ZERO_ADDRESS)
    receiverShares = receiverShares.add(100)
    expect(await osToken.balanceOf(treasury)).to.be.above(0)
    expect(await osToken.cumulativeFeePerShare()).to.be.above(cumulativeFeePerShare)

    cumulativeFeePerShare = await osToken.cumulativeFeePerShare()
    treasuryShares = await osToken.balanceOf(treasury)
    positionShares = treasuryShares.add(receiverShares)
    totalShares = positionShares
    totalAssets = await osToken.convertToAssets(positionShares)
    await verify()

    await snapshotGasCost(receipt)
  })

  it('mints osTokens to the receiver', async () => {
    const receipt = await vault
      .connect(sender)
      .mintOsToken(receiver.address, osTokenShares, ZERO_ADDRESS)
    const osTokenAssets = await vault.convertToAssets(osTokenShares)

    expect(await osToken.convertToShares(osTokenAssets)).to.eq(osTokenShares)
    expect(await osToken.balanceOf(receiver.address)).to.eq(osTokenShares)
    expect(await vault.osTokenPositions(sender.address)).to.eq(osTokenShares)
    await expect(receipt)
      .to.emit(vault, 'OsTokenMinted')
      .withArgs(sender.address, receiver.address, osTokenAssets, osTokenShares, ZERO_ADDRESS)
    await expect(receipt)
      .to.emit(osToken, 'Transfer')
      .withArgs(ZERO_ADDRESS, receiver.address, osTokenShares)
    await expect(receipt)
      .to.emit(osToken, 'Mint')
      .withArgs(vault.address, receiver.address, osTokenAssets, osTokenShares)

    await snapshotGasCost(receipt)
  })
})
