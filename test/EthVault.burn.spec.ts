import { ethers, waffle } from 'hardhat'
import { BigNumber, Contract, Wallet } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import { EthVault, Keeper, OsToken, UnknownVaultMock } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import snapshotGasCost from './shared/snapshotGasCost'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { ONE_DAY, ZERO_ADDRESS } from './shared/constants'
import { collateralizeEthVault } from './shared/rewards'
import { increaseTime } from './shared/utils'

const createFixtureLoader = waffle.createFixtureLoader

describe('EthVault - burn', () => {
  const assets = parseEther('2')
  const osTokenAssets = parseEther('1')
  const osTokenShares = parseEther('1')
  const vaultParams = {
    capacity: parseEther('1000'),
    feePercent: 1000,
    metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u',
  }
  let sender: Wallet, admin: Wallet, owner: Wallet
  let vault: EthVault, keeper: Keeper, osToken: OsToken, validatorsRegistry: Contract

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthVault']

  before('create fixture loader', async () => {
    ;[sender, owner, admin] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([owner])
  })

  beforeEach('deploy fixture', async () => {
    ;({
      createEthVault: createVault,
      keeper,
      validatorsRegistry,
      osToken,
    } = await loadFixture(ethVaultFixture))
    vault = await createVault(admin, vaultParams)
    await osToken.connect(owner).setVaultImplementation(await vault.implementation(), true)

    // collateralize vault
    await collateralizeEthVault(vault, keeper, validatorsRegistry, admin)
    await vault.connect(sender).deposit(sender.address, ZERO_ADDRESS, { value: assets })
    await vault.connect(sender).mintOsToken(sender.address, osTokenShares, ZERO_ADDRESS)
  })

  it('cannot burn zero osTokens', async () => {
    await expect(vault.connect(sender).burnOsToken(0)).to.be.revertedWith('InvalidShares')
  })

  it('cannot burn osTokens when nothing is minted', async () => {
    await osToken.connect(sender).transfer(owner.address, osTokenShares)
    await expect(vault.connect(owner).burnOsToken(osTokenShares)).to.be.revertedWith(
      'InvalidPosition'
    )
  })

  it('cannot burn osTokens from unregistered vault', async () => {
    const factory = await ethers.getContractFactory('UnknownVaultMock')
    const unknownVault = (await factory.deploy(
      osToken.address,
      await vault.implementation()
    )) as UnknownVaultMock
    await expect(unknownVault.connect(sender).burnOsToken(osTokenShares)).to.be.revertedWith(
      'AccessDenied'
    )
  })

  it('updates position accumulated fee', async () => {
    const treasury = await osToken.treasury()
    let totalShares = osTokenShares
    let totalAssets = osTokenAssets
    let cumulativeFeePerShare = BigNumber.from(0)
    let treasuryShares = BigNumber.from(0)
    let positionShares = osTokenShares

    expect(await osToken.cumulativeFeePerShare()).to.eq(0)
    expect(await vault.osTokenPositions(sender.address)).to.eq(positionShares)

    await increaseTime(ONE_DAY)

    expect(await osToken.cumulativeFeePerShare()).to.be.above(cumulativeFeePerShare)
    expect(await osToken.totalAssets()).to.be.above(totalAssets)
    expect(await vault.osTokenPositions(sender.address)).to.be.above(positionShares)

    const receipt = await vault.connect(sender).burnOsToken(osTokenShares)
    expect(await osToken.balanceOf(treasury)).to.be.above(0)
    expect(await osToken.cumulativeFeePerShare()).to.be.above(cumulativeFeePerShare)
    await snapshotGasCost(receipt)

    cumulativeFeePerShare = await osToken.cumulativeFeePerShare()
    treasuryShares = await osToken.balanceOf(treasury)
    positionShares = treasuryShares
    totalShares = treasuryShares
    totalAssets = await osToken.convertToAssets(treasuryShares)
    expect(await osToken.totalSupply()).to.eq(totalShares)
    expect(await osToken.totalAssets()).to.eq(totalAssets)
    expect(await osToken.cumulativeFeePerShare()).to.eq(cumulativeFeePerShare)
    expect(await osToken.balanceOf(treasury)).to.eq(treasuryShares)
    expect(await osToken.balanceOf(sender.address)).to.eq(0)
    expect(await vault.osTokenPositions(sender.address)).to.eq(positionShares)
  })

  it('burns osTokens', async () => {
    const tx = await vault.connect(sender).burnOsToken(osTokenShares)
    const receipt = await tx.wait()
    // eslint-disable-next-line @typescript-eslint/ban-ts-comment
    // @ts-ignore
    const osTokenAssets = receipt?.events?.find((e: any) => e.event === 'OsTokenBurned')?.args[1]

    expect(await osToken.balanceOf(sender.address)).to.eq(0)
    expect(await vault.osTokenPositions(sender.address)).to.eq(
      await osToken.balanceOf(await osToken.treasury())
    )
    await expect(tx)
      .to.emit(vault, 'OsTokenBurned')
      .withArgs(sender.address, osTokenAssets, osTokenShares)
    await expect(tx)
      .to.emit(osToken, 'Transfer')
      .withArgs(sender.address, ZERO_ADDRESS, osTokenShares)
    await expect(tx)
      .to.emit(osToken, 'Burn')
      .withArgs(vault.address, sender.address, osTokenAssets, osTokenShares)

    await snapshotGasCost(receipt)
  })
})
