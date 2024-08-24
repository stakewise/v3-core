import { ethers } from 'hardhat'
import { Signer, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  ERC20Mock,
  GnoVault,
  IKeeperRewards,
  Keeper,
  OsTokenVaultEscrow,
  OsTokenVaultEscrowAuthMock,
  OsTokenVaultEscrowAuthMock__factory,
} from '../../typechain-types'
import { collateralizeGnoVault, depositGno, gnoVaultFixture } from '../shared/gnoFixtures'
import { EXITING_ASSETS_MIN_DELAY, ZERO_ADDRESS } from '../shared/constants'
import { getHarvestParams, getRewardsRootProof, updateRewards } from '../shared/rewards'
import { extractExitPositionTicket, getBlockTimestamp, increaseTime } from '../shared/utils'
import { expect } from '../shared/expect'

describe('GnoOsTokenVaultEscrow', () => {
  const assets = ethers.parseEther('100')
  const vaultParams = {
    capacity: ethers.parseEther('1000'),
    feePercent: 1000,
    metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u',
  }
  let dao: Wallet, admin: Signer, owner: Wallet
  let vault: GnoVault,
    osTokenVaultEscrow: OsTokenVaultEscrow,
    osTokenVaultEscrowAuth: OsTokenVaultEscrowAuthMock,
    keeper: Keeper,
    gnoToken: ERC20Mock
  let vaultAddr: string
  let osTokenShares: bigint

  beforeEach('deploy fixture', async () => {
    ;[dao, admin, owner] = await (ethers as any).getSigners()
    const fixture = await loadFixture(gnoVaultFixture)
    vault = await fixture.createGnoVault(admin, vaultParams)
    vaultAddr = await vault.getAddress()
    admin = await ethers.getImpersonatedSigner(await vault.admin())
    osTokenVaultEscrow = fixture.osTokenVaultEscrow
    keeper = fixture.keeper
    gnoToken = fixture.gnoToken
    osTokenVaultEscrowAuth = OsTokenVaultEscrowAuthMock__factory.connect(
      await osTokenVaultEscrow.authenticator(),
      dao
    )
    await osTokenVaultEscrowAuth.setCanRegister(owner.address, true)

    // collateralize vault
    await collateralizeGnoVault(
      vault,
      fixture.gnoToken,
      fixture.keeper,
      fixture.depositDataRegistry,
      admin as Wallet,
      fixture.validatorsRegistry
    )
    await depositGno(vault, gnoToken, assets, owner, owner, ZERO_ADDRESS)
    osTokenShares = await fixture.osTokenVaultController.convertToShares(assets / 2n)
    await vault.connect(owner).mintOsToken(owner.address, osTokenShares, ZERO_ADDRESS)
  })

  it('succeeds', async () => {
    const exitOsTokenShares = await vault.osTokenPositions(owner.address)
    let tx = await vault.connect(owner).transferOsTokenPositionToEscrow(exitOsTokenShares)
    const positionTicket = await extractExitPositionTicket(tx)
    const timestamp = await getBlockTimestamp(tx)

    const vaultReward = getHarvestParams(vaultAddr, 0n, 0n)
    const tree = await updateRewards(keeper, [vaultReward], 0)
    const harvestParams: IKeeperRewards.HarvestParamsStruct = {
      rewardsRoot: tree.root,
      reward: vaultReward.reward,
      unlockedMevReward: vaultReward.unlockedMevReward,
      proof: getRewardsRootProof(tree, vaultReward),
    }
    await vault.connect(dao).updateState(harvestParams)
    await increaseTime(EXITING_ASSETS_MIN_DELAY)

    const index = await vault.getExitQueueIndex(positionTicket)
    await osTokenVaultEscrow
      .connect(owner)
      .processExitedAssets(vaultAddr, positionTicket, timestamp, index)
    const balanceBefore = await gnoToken.balanceOf(owner.address)
    tx = await osTokenVaultEscrow
      .connect(owner)
      .claimExitedAssets(vaultAddr, positionTicket, exitOsTokenShares)
    const balanceAfter = await gnoToken.balanceOf(owner.address)
    expect(balanceAfter).to.be.greaterThan(balanceBefore)
    await expect(tx).to.emit(osTokenVaultEscrow, 'ExitedAssetsClaimed')
  })
})
