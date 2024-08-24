import { ethers } from 'hardhat'
import { parseEther, Signer, Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { expect } from './shared/expect'
import {
  EthVault,
  IKeeperRewards,
  Keeper,
  OsToken,
  OsTokenConfig,
  OsTokenVaultController,
  OsTokenVaultEscrow,
  OsTokenVaultEscrowAuthMock,
  OsTokenVaultEscrowAuthMock__factory,
} from '../typechain-types'
import { ethVaultFixture } from './shared/fixtures'
import {
  EXITING_ASSETS_MIN_DELAY,
  MAX_UINT256,
  OSTOKEN_VAULT_ESCROW_LIQ_BONUS,
  OSTOKEN_VAULT_ESCROW_LIQ_THRESHOLD,
  PANIC_CODES,
  ZERO_ADDRESS,
} from './shared/constants'
import {
  collateralizeEthVault,
  getHarvestParams,
  getRewardsRootProof,
  setAvgRewardPerSecond,
  updateRewards,
} from './shared/rewards'
import snapshotGasCost from './shared/snapshotGasCost'
import {
  extractExitPositionTicket,
  getBlockTimestamp,
  getGasUsed,
  increaseTime,
  setBalance,
} from './shared/utils'

describe('EthOsTokenVaultEscrow', () => {
  const assets = ethers.parseEther('100')
  const vaultParams = {
    capacity: ethers.parseEther('1000'),
    feePercent: 1000,
    metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u',
  }
  let dao: Wallet, admin: Signer, owner: Wallet, other: Wallet, redeemer: Wallet, liquidator: Wallet
  let vault: EthVault,
    osToken: OsToken,
    osTokenConfig: OsTokenConfig,
    osTokenVaultEscrow: OsTokenVaultEscrow,
    osTokenVaultController: OsTokenVaultController,
    osTokenVaultEscrowAuth: OsTokenVaultEscrowAuthMock,
    keeper: Keeper
  let vaultAddr: string
  let osTokenShares: bigint

  beforeEach('deploy fixture', async () => {
    ;[dao, admin, owner, redeemer, liquidator, other] = await (ethers as any).getSigners()
    const fixture = await loadFixture(ethVaultFixture)
    vault = await fixture.createEthVault(admin, vaultParams)
    vaultAddr = await vault.getAddress()
    admin = await ethers.getImpersonatedSigner(await vault.admin())
    osTokenVaultEscrow = fixture.osTokenVaultEscrow
    osTokenVaultController = fixture.osTokenVaultController
    keeper = fixture.keeper
    osToken = fixture.osToken
    osTokenConfig = fixture.osTokenConfig
    osTokenVaultEscrowAuth = OsTokenVaultEscrowAuthMock__factory.connect(
      await osTokenVaultEscrow.authenticator(),
      dao
    )
    await osTokenVaultEscrowAuth.setCanRegister(owner.address, true)

    // collateralize vault
    await collateralizeEthVault(
      vault,
      fixture.keeper,
      fixture.depositDataRegistry,
      admin,
      fixture.validatorsRegistry
    )
    await vault
      .connect(owner)
      .depositAndMintOsToken(owner.address, MAX_UINT256, ZERO_ADDRESS, { value: assets })
    osTokenShares = await fixture.osToken.balanceOf(owner.address)
  })

  describe('register', () => {
    it('cannot register when vault is not harvested', async () => {
      await updateRewards(
        keeper,
        [
          {
            vault: vaultAddr,
            reward: 0n,
            unlockedMevReward: 0n,
          },
        ],
        0
      )
      await updateRewards(
        keeper,
        [
          {
            vault: vaultAddr,
            reward: 0n,
            unlockedMevReward: 0n,
          },
        ],
        0
      )
      await expect(
        vault.connect(owner).transferOsTokenPositionToEscrow(osTokenShares)
      ).to.be.revertedWithCustomError(vault, 'NotHarvested')
    })

    it('cannot register with invalid osToken position', async () => {
      await expect(
        vault.connect(other).transferOsTokenPositionToEscrow(osTokenShares)
      ).to.be.revertedWithCustomError(vault, 'InvalidShares')
      await expect(
        vault.connect(owner).transferOsTokenPositionToEscrow(0n)
      ).to.be.revertedWithCustomError(vault, 'InvalidShares')

      await expect(
        vault.connect(owner).transferOsTokenPositionToEscrow(osTokenShares * 2n)
      ).to.be.revertedWithCustomError(vault, 'InvalidShares')
    })

    it('removes position if all the osToken shares transferred', async () => {
      await setAvgRewardPerSecond(dao, vault, keeper, 0)
      const cumulativeFeePerShare = await osTokenVaultController.cumulativeFeePerShare()
      const sharesToRegister = await vault.osTokenPositions(owner.address)
      const tx = await vault.connect(owner).transferOsTokenPositionToEscrow(sharesToRegister)
      const positionTicket = await extractExitPositionTicket(tx)
      await expect(tx)
        .to.emit(osTokenVaultEscrow, 'PositionCreated')
        .withArgs(vaultAddr, positionTicket, owner.address, sharesToRegister, cumulativeFeePerShare)
      expect(await vault.osTokenPositions(owner.address)).to.equal(0n)
      expect(await vault.getShares(owner.address)).to.equal(0n)

      const escrowPosition = await osTokenVaultEscrow.getPosition(vaultAddr, positionTicket)
      expect(escrowPosition[0]).to.equal(0n)
      expect(escrowPosition[1]).to.equal(sharesToRegister)
      await snapshotGasCost(tx)
    })

    it('keeps LTV for the position left', async () => {
      await setAvgRewardPerSecond(dao, vault, keeper, 0)
      const cumulativeFeePerShare = await osTokenVaultController.cumulativeFeePerShare()

      let sharesToRegister = await vault.osTokenPositions(owner.address)
      const stakedShares = await vault.getShares(owner.address)
      const vaultLtvBefore =
        ((await osTokenVaultController.convertToAssets(sharesToRegister)) * 1000n) /
        (await vault.convertToAssets(stakedShares))

      sharesToRegister /= 2n
      const tx = await vault.connect(owner).transferOsTokenPositionToEscrow(sharesToRegister)
      const positionTicket = await extractExitPositionTicket(tx)
      await expect(tx)
        .to.emit(osTokenVaultEscrow, 'PositionCreated')
        .withArgs(vaultAddr, positionTicket, owner.address, sharesToRegister, cumulativeFeePerShare)
      expect(await vault.osTokenPositions(owner.address)).to.equal(sharesToRegister)
      expect(await vault.getShares(owner.address)).to.equal(stakedShares / 2n)

      const vaultLtvAfter =
        ((await osTokenVaultController.convertToAssets(sharesToRegister)) * 1000n) /
        (await vault.convertToAssets(await vault.getShares(owner.address)))
      expect(vaultLtvAfter).to.equal(vaultLtvBefore)

      const escrowPosition = await osTokenVaultEscrow.getPosition(vaultAddr, positionTicket)
      expect(escrowPosition[0]).to.equal(0n)
      expect(escrowPosition[1]).to.equal(sharesToRegister)
      await snapshotGasCost(tx)
    })

    it('cannot register with failed authenticator check', async () => {
      await osTokenVaultEscrowAuth.setCanRegister(owner.address, false)
      await expect(
        vault.connect(owner).transferOsTokenPositionToEscrow(osTokenShares)
      ).to.be.revertedWithCustomError(osTokenVaultEscrow, 'AccessDenied')
    })

    it('cannot register with zero owner address', async () => {
      await osTokenVaultEscrowAuth.setCanRegister(ZERO_ADDRESS, true)
      await expect(
        osTokenVaultEscrow.connect(owner).register(ZERO_ADDRESS, 0n, osTokenShares, 0n)
      ).to.be.revertedWithCustomError(osTokenVaultEscrow, 'ZeroAddress')
    })

    it('cannot register with zero osToken shares', async () => {
      await expect(
        osTokenVaultEscrow.connect(owner).register(owner.address, 0n, 0n, 0n)
      ).to.be.revertedWithCustomError(osTokenVaultEscrow, 'InvalidShares')
    })
  })

  describe('process exited assets', () => {
    let positionTicket: bigint
    let timestamp: number
    let exitOsTokenShares: bigint

    beforeEach('register position', async () => {
      exitOsTokenShares = await vault.osTokenPositions(owner.address)
      const tx = await vault.connect(owner).transferOsTokenPositionToEscrow(exitOsTokenShares)
      positionTicket = await extractExitPositionTicket(tx)
      timestamp = await getBlockTimestamp(tx)
    })

    it('cannot process with invalid position ticket', async () => {
      await expect(
        osTokenVaultEscrow.connect(owner).processExitedAssets(vaultAddr, 0n, timestamp, 0n)
      ).to.be.revertedWithCustomError(osTokenVaultEscrow, 'InvalidPosition')
    })

    it('cannot process with invalid index', async () => {
      await expect(
        osTokenVaultEscrow
          .connect(owner)
          .processExitedAssets(vaultAddr, positionTicket, timestamp, 0n)
      ).to.be.revertedWithCustomError(vault, 'InvalidCheckpointIndex')
    })

    it('cannot process partially exited position', async () => {
      await setBalance(vaultAddr, assets / 2n)
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
      await expect(
        osTokenVaultEscrow
          .connect(owner)
          .processExitedAssets(vaultAddr, positionTicket, timestamp, index)
      ).to.be.revertedWithCustomError(osTokenVaultEscrow, 'ExitRequestNotProcessed')
    })

    it('processes exited assets', async () => {
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
      const exitPosition = await vault.calculateExitedAssets(
        await osTokenVaultEscrow.getAddress(),
        positionTicket,
        timestamp,
        index
      )
      const tx = await osTokenVaultEscrow
        .connect(other)
        .processExitedAssets(vaultAddr, positionTicket, timestamp, index)
      await expect(tx)
        .to.emit(osTokenVaultEscrow, 'ExitedAssetsProcessed')
        .withArgs(vaultAddr, other.address, positionTicket, exitPosition.exitedAssets)

      const escrowPosition = await osTokenVaultEscrow.getPosition(vaultAddr, positionTicket)
      expect(escrowPosition[0]).to.equal(exitPosition.exitedAssets)
      // accumulates fee
      expect(escrowPosition[1]).to.greaterThan(exitOsTokenShares)
      await snapshotGasCost(tx)
    })
  })

  describe('claim exited assets', () => {
    let positionTicket: bigint
    let timestamp: number
    let exitOsTokenShares: bigint

    beforeEach('register position', async () => {
      exitOsTokenShares = await osToken.balanceOf(owner.address)
      const tx = await vault.connect(owner).transferOsTokenPositionToEscrow(exitOsTokenShares)
      positionTicket = await extractExitPositionTicket(tx)
      timestamp = await getBlockTimestamp(tx)
    })

    it('fails when not enough osToken shares', async () => {
      await expect(
        osTokenVaultEscrow
          .connect(owner)
          .claimExitedAssets(vaultAddr, positionTicket, exitOsTokenShares + 1n)
      ).to.be.revertedWithCustomError(osToken, 'ERC20InsufficientBalance')
    })

    it('fails from not position owner', async () => {
      await osToken.connect(owner).transfer(other.address, exitOsTokenShares)
      await expect(
        osTokenVaultEscrow
          .connect(other)
          .claimExitedAssets(vaultAddr, positionTicket, exitOsTokenShares)
      ).to.be.revertedWithCustomError(osTokenVaultEscrow, 'AccessDenied')
    })

    it('fails with more osToken shares than available', async () => {
      await vault.depositAndMintOsToken(owner.address, MAX_UINT256, ZERO_ADDRESS, {
        value: assets,
      })
      const osTokenShares = await osToken.balanceOf(owner.address)
      await expect(
        osTokenVaultEscrow
          .connect(owner)
          .claimExitedAssets(vaultAddr, positionTicket, osTokenShares)
      ).to.be.revertedWithCustomError(osTokenVaultEscrow, 'InvalidShares')
    })

    it('fails for not processed exited assets', async () => {
      await expect(
        osTokenVaultEscrow
          .connect(owner)
          .claimExitedAssets(vaultAddr, positionTicket, exitOsTokenShares)
      ).to.be.revertedWithCustomError(osTokenVaultEscrow, 'ExitRequestNotProcessed')
    })

    describe('succeeds', async () => {
      let exitedAssets: bigint

      beforeEach('process exited assets', async () => {
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
        const exitPosition = await vault.calculateExitedAssets(
          await osTokenVaultEscrow.getAddress(),
          positionTicket,
          timestamp,
          index
        )
        exitedAssets = exitPosition.exitedAssets

        await osTokenVaultEscrow
          .connect(owner)
          .processExitedAssets(vaultAddr, positionTicket, timestamp, index)
      })

      it('succeeds for partial osToken shares', async () => {
        await setAvgRewardPerSecond(dao, vault, keeper, 0)
        const osTokenSharesToBurn = exitOsTokenShares / 2n
        let escrowPosition = await osTokenVaultEscrow.getPosition(vaultAddr, positionTicket)
        const totalOsTokenShares = escrowPosition[1]

        const assetsToWithdraw = (exitedAssets * osTokenSharesToBurn) / totalOsTokenShares
        const balanceBefore = await ethers.provider.getBalance(owner.address)
        const tx = await osTokenVaultEscrow
          .connect(owner)
          .claimExitedAssets(vaultAddr, positionTicket, osTokenSharesToBurn)
        const balanceAfter = await ethers.provider.getBalance(owner.address)
        const gasUsed = await getGasUsed(tx)
        expect(balanceAfter - balanceBefore).to.equal(assetsToWithdraw - gasUsed)
        await expect(tx)
          .to.emit(osTokenVaultEscrow, 'ExitedAssetsClaimed')
          .withArgs(owner.address, vaultAddr, positionTicket, osTokenSharesToBurn, assetsToWithdraw)

        escrowPosition = await osTokenVaultEscrow.getPosition(vaultAddr, positionTicket)
        expect(escrowPosition[0]).to.equal(exitedAssets - assetsToWithdraw)
        expect(escrowPosition[1]).to.equal(totalOsTokenShares - osTokenSharesToBurn)
        await snapshotGasCost(tx)
      })

      it('succeeds for all osToken shares', async () => {
        await setAvgRewardPerSecond(dao, vault, keeper, 0)
        await vault.depositAndMintOsToken(owner.address, MAX_UINT256, ZERO_ADDRESS, {
          value: assets,
        })

        let escrowPosition = await osTokenVaultEscrow.getPosition(vaultAddr, positionTicket)
        const osTokenSharesToBurn = escrowPosition[1]
        const assetsToWithdraw = exitedAssets
        const balanceBefore = await ethers.provider.getBalance(owner.address)
        const tx = await osTokenVaultEscrow
          .connect(owner)
          .claimExitedAssets(vaultAddr, positionTicket, osTokenSharesToBurn)
        const balanceAfter = await ethers.provider.getBalance(owner.address)
        const gasUsed = await getGasUsed(tx)
        expect(balanceAfter - balanceBefore).to.equal(assetsToWithdraw - gasUsed)
        await expect(tx)
          .to.emit(osTokenVaultEscrow, 'ExitedAssetsClaimed')
          .withArgs(owner.address, vaultAddr, positionTicket, osTokenSharesToBurn, assetsToWithdraw)

        escrowPosition = await osTokenVaultEscrow.getPosition(vaultAddr, positionTicket)
        expect(escrowPosition[0]).to.equal(0n)
        expect(escrowPosition[1]).to.equal(0n)
        await snapshotGasCost(tx)
      })
    })
  })

  describe('redeem', () => {
    let positionTicket: bigint
    let redeemedShares: bigint
    let exitedAssets: bigint

    beforeEach('register position', async () => {
      const tx = await vault
        .connect(owner)
        .transferOsTokenPositionToEscrow(await vault.osTokenPositions(owner.address))
      positionTicket = await extractExitPositionTicket(tx)
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
        .connect(other)
        .processExitedAssets(vaultAddr, positionTicket, timestamp, index)

      const escrowPosition = await osTokenVaultEscrow.getPosition(vaultAddr, positionTicket)
      exitedAssets = escrowPosition[0]
      redeemedShares = escrowPosition[1]

      const redeemAssets = await osTokenVaultController.convertToAssets(redeemedShares)
      const vaultConfig = await osTokenConfig.getConfig(vaultAddr)
      await osTokenConfig.connect(dao).setRedeemer(redeemer.address)
      await vault
        .connect(redeemer)
        .depositAndMintOsToken(redeemer.address, MAX_UINT256, ZERO_ADDRESS, {
          value: (redeemAssets * parseEther('1.1')) / vaultConfig.ltvPercent,
        })
    })

    it('cannot redeem osTokens from not redeemer', async () => {
      await osTokenConfig.connect(dao).setRedeemer(dao.address)
      await expect(
        osTokenVaultEscrow
          .connect(redeemer)
          .redeemOsToken(vaultAddr, positionTicket, redeemedShares, redeemer.address)
      ).to.be.revertedWithCustomError(vault, 'AccessDenied')
    })

    it('cannot redeem osTokens to zero receiver', async () => {
      await expect(
        osTokenVaultEscrow
          .connect(redeemer)
          .redeemOsToken(vaultAddr, positionTicket, redeemedShares, ZERO_ADDRESS)
      ).to.be.revertedWithCustomError(vault, 'ZeroAddress')
    })

    it('cannot redeem osTokens for position with zero minted shares', async () => {
      await expect(
        osTokenVaultEscrow
          .connect(redeemer)
          .redeemOsToken(vaultAddr, positionTicket + 1n, redeemedShares, redeemer.address)
      ).to.be.revertedWithCustomError(vault, 'InvalidPosition')
    })

    it('cannot redeem osTokens when received assets exceed exited assets', async () => {
      const redeemedShares = await osTokenVaultController.convertToShares(exitedAssets * 3n)
      await expect(
        osTokenVaultEscrow
          .connect(redeemer)
          .redeemOsToken(vaultAddr, positionTicket, redeemedShares, redeemer.address)
      ).to.be.revertedWithCustomError(vault, 'InvalidReceivedAssets')
    })

    it('cannot redeem osTokens when redeeming more than minted', async () => {
      await setAvgRewardPerSecond(dao, vault, keeper, 0)
      const escrowPosition = await osTokenVaultEscrow.getPosition(vaultAddr, positionTicket)
      const redeemedShares = escrowPosition[1] + 1n
      await expect(
        osTokenVaultEscrow
          .connect(redeemer)
          .redeemOsToken(vaultAddr, positionTicket, redeemedShares, redeemer.address)
      ).to.be.revertedWithPanic(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
    })

    it('cannot redeem zero osToken shares', async () => {
      await expect(
        osTokenVaultEscrow
          .connect(redeemer)
          .redeemOsToken(vaultAddr, positionTicket, 0, redeemer.address)
      ).to.be.revertedWithCustomError(osTokenVaultController, 'InvalidShares')
    })

    it('cannot redeem without osTokens', async () => {
      await osToken.connect(redeemer).transfer(dao.address, redeemedShares)
      await expect(
        osTokenVaultEscrow
          .connect(redeemer)
          .redeemOsToken(vaultAddr, positionTicket, redeemedShares, redeemer.address)
      ).to.be.revertedWithCustomError(osToken, 'ERC20InsufficientBalance')
    })

    it('can redeem', async () => {
      await setAvgRewardPerSecond(dao, vault, keeper, 0)

      const osTokenBalanceBefore = await osToken.balanceOf(redeemer.address)
      const escrowPositionBefore = await osTokenVaultEscrow.getPosition(vaultAddr, positionTicket)
      const assetsBalanceBefore = await ethers.provider.getBalance(redeemer.address)

      const receipt = await osTokenVaultEscrow
        .connect(redeemer)
        .redeemOsToken(vaultAddr, positionTicket, redeemedShares, redeemer.address)

      let redeemedAssets = await osTokenVaultController.convertToAssets(redeemedShares)
      const escrowPositionAfter = await osTokenVaultEscrow.getPosition(vaultAddr, positionTicket)
      const assetsBalanceAfter = await ethers.provider.getBalance(redeemer.address)
      const gasUsed = await getGasUsed(receipt)

      expect(await osToken.balanceOf(redeemer.address)).to.eq(osTokenBalanceBefore - redeemedShares)
      expect(escrowPositionAfter[1]).to.be.eq(escrowPositionBefore[1] - redeemedShares)

      try {
        await expect(receipt)
          .to.emit(osTokenVaultEscrow, 'OsTokenRedeemed')
          .withArgs(
            redeemer.address,
            vaultAddr,
            positionTicket,
            redeemer.address,
            redeemedShares,
            redeemedAssets
          )
      } catch {
        redeemedAssets -= 1n // rounding error
        await expect(receipt)
          .to.emit(osTokenVaultEscrow, 'OsTokenRedeemed')
          .withArgs(
            redeemer.address,
            vaultAddr,
            positionTicket,
            redeemer.address,
            redeemedShares,
            redeemedAssets
          )
      }

      expect(escrowPositionAfter[0]).to.be.eq(escrowPositionBefore[0] - redeemedAssets)
      expect(assetsBalanceAfter).to.eq(assetsBalanceBefore + redeemedAssets - gasUsed)

      await expect(receipt)
        .to.emit(osToken, 'Transfer')
        .withArgs(redeemer.address, ZERO_ADDRESS, redeemedShares)
      await expect(receipt)
        .to.emit(osTokenVaultController, 'Burn')
        .withArgs(
          await osTokenVaultEscrow.getAddress(),
          redeemer.address,
          redeemedAssets,
          redeemedShares
        )

      await snapshotGasCost(receipt)
    })
  })

  describe('liquidate', () => {
    let positionTicket: bigint
    let liquidatedShares: bigint

    beforeEach('register position', async () => {
      const tx = await vault
        .connect(owner)
        .transferOsTokenPositionToEscrow(await vault.osTokenPositions(owner.address))
      positionTicket = await extractExitPositionTicket(tx)
      const timestamp = await getBlockTimestamp(tx)

      // slash 20% of assets
      const penalty = -(await vault.totalAssets()) / 5n

      // slashing received
      const vaultReward = getHarvestParams(await vault.getAddress(), penalty, 0n)
      const tree = await updateRewards(keeper, [vaultReward], 0)
      const harvestParams = {
        rewardsRoot: tree.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof: getRewardsRootProof(tree, vaultReward),
      }
      await vault.connect(dao).updateState(harvestParams)
      await increaseTime(EXITING_ASSETS_MIN_DELAY)

      const index = await vault.getExitQueueIndex(positionTicket)
      await osTokenVaultEscrow
        .connect(other)
        .processExitedAssets(vaultAddr, positionTicket, timestamp, index)

      const escrowPosition = await osTokenVaultEscrow.getPosition(vaultAddr, positionTicket)
      liquidatedShares = escrowPosition[1]
      const liquidatedAssets = await osTokenVaultController.convertToAssets(liquidatedShares)

      const vaultConfig = await osTokenConfig.getConfig(vaultAddr)
      await vault.depositAndMintOsToken(liquidator.address, MAX_UINT256, ZERO_ADDRESS, {
        value: (liquidatedAssets * parseEther('1.1')) / vaultConfig.ltvPercent,
      })
    })

    it('cannot liquidate osTokens when received assets exceed exited assets', async () => {
      await expect(
        osTokenVaultEscrow
          .connect(liquidator)
          .liquidateOsToken(vaultAddr, positionTicket, liquidatedShares, liquidator.address)
      ).to.be.revertedWithCustomError(vault, 'InvalidReceivedAssets')
    })

    it('cannot liquidate osTokens when health factor is above 1', async () => {
      await vault.connect(other).depositAndMintOsToken(other.address, MAX_UINT256, ZERO_ADDRESS, {
        value: assets,
      })
      await osTokenVaultEscrowAuth.setCanRegister(other.address, true)
      const tx = await vault
        .connect(other)
        .transferOsTokenPositionToEscrow(await vault.osTokenPositions(other.address))
      const positionTicket = await extractExitPositionTicket(tx)
      const timestamp = await getBlockTimestamp(tx)
      const vaultReward = getHarvestParams(vaultAddr, 0n, 0n)
      const tree = await updateRewards(keeper, [vaultReward], 0)
      const harvestParams = {
        rewardsRoot: tree.root,
        reward: vaultReward.reward,
        unlockedMevReward: vaultReward.unlockedMevReward,
        proof: getRewardsRootProof(tree, vaultReward),
      }
      await vault.connect(dao).updateState(harvestParams)
      await increaseTime(EXITING_ASSETS_MIN_DELAY)

      const index = await vault.getExitQueueIndex(positionTicket)
      await osTokenVaultEscrow
        .connect(other)
        .processExitedAssets(vaultAddr, positionTicket, timestamp, index)

      await expect(
        osTokenVaultEscrow
          .connect(liquidator)
          .liquidateOsToken(vaultAddr, positionTicket, liquidatedShares, liquidator.address)
      ).to.be.revertedWithCustomError(vault, 'InvalidHealthFactor')
    })

    it('can liquidate', async () => {
      const osTokenBalanceBefore = await osToken.balanceOf(liquidator.address)
      const escrowPositionBefore = await osTokenVaultEscrow.getPosition(vaultAddr, positionTicket)
      const assetsBalanceBefore = await ethers.provider.getBalance(liquidator.address)

      let receivedAssets = escrowPositionBefore[0]
      const liquidatedShares = await osTokenVaultController.convertToShares(
        (receivedAssets * parseEther('1')) / (await osTokenVaultEscrow.liqBonusPercent())
      )
      receivedAssets -= 2n // rounding error

      const receipt = await osTokenVaultEscrow
        .connect(liquidator)
        .liquidateOsToken(vaultAddr, positionTicket, liquidatedShares, liquidator.address)

      const escrowPositionAfter = await osTokenVaultEscrow.getPosition(vaultAddr, positionTicket)
      const assetsBalanceAfter = await ethers.provider.getBalance(liquidator.address)
      const gasUsed = await getGasUsed(receipt)

      expect(await osToken.balanceOf(liquidator.address)).to.eq(
        osTokenBalanceBefore - liquidatedShares
      )
      expect(escrowPositionAfter[0]).to.be.eq(escrowPositionBefore[0] - receivedAssets)
      expect(escrowPositionAfter[1]).to.be.eq(escrowPositionBefore[1] - liquidatedShares)
      await expect(receipt)
        .to.emit(osTokenVaultEscrow, 'OsTokenLiquidated')
        .withArgs(
          liquidator.address,
          vaultAddr,
          positionTicket,
          liquidator.address,
          liquidatedShares,
          receivedAssets
        )

      expect(assetsBalanceAfter).to.eq(assetsBalanceBefore + receivedAssets - gasUsed)

      await expect(receipt)
        .to.emit(osToken, 'Transfer')
        .withArgs(liquidator.address, ZERO_ADDRESS, liquidatedShares)
      await expect(receipt).to.emit(osTokenVaultController, 'Burn')

      await snapshotGasCost(receipt)
    })
  })

  describe('set authenticator', () => {
    it('fails with the same value', async () => {
      await expect(
        osTokenVaultEscrow.connect(dao).setAuthenticator(await osTokenVaultEscrow.authenticator())
      ).to.be.revertedWithCustomError(osTokenVaultEscrow, 'ValueNotChanged')
    })
    it('fails from not owner', async () => {
      await expect(
        osTokenVaultEscrow.connect(other).setAuthenticator(other.address)
      ).to.be.revertedWithCustomError(osTokenVaultEscrow, 'OwnableUnauthorizedAccount')
    })

    it('owner can update authenticator', async () => {
      const tx = await osTokenVaultEscrow.connect(dao).setAuthenticator(other.address)
      expect(await osTokenVaultEscrow.authenticator()).to.be.eq(other.address)
      await expect(tx).to.emit(osTokenVaultEscrow, 'AuthenticatorUpdated').withArgs(other.address)
      await snapshotGasCost(tx)
    })
  })

  describe('update config', () => {
    const newLiqThresholdPercent = OSTOKEN_VAULT_ESCROW_LIQ_THRESHOLD - 1n
    const newLiqBonusPercent = OSTOKEN_VAULT_ESCROW_LIQ_BONUS - 1n
    const maxPercent = parseEther('1')

    it('updates in constructor', async () => {
      expect(await osTokenVaultEscrow.liqThresholdPercent()).to.be.eq(
        OSTOKEN_VAULT_ESCROW_LIQ_THRESHOLD
      )
      expect(await osTokenVaultEscrow.liqBonusPercent()).to.be.eq(OSTOKEN_VAULT_ESCROW_LIQ_BONUS)
    })

    it('not owner cannot update config', async () => {
      await expect(
        osTokenVaultEscrow.connect(other).updateConfig(newLiqThresholdPercent, newLiqBonusPercent)
      ).to.revertedWithCustomError(osTokenConfig, 'OwnableUnauthorizedAccount')
    })

    it('fails with invalid liqThresholdPercent', async () => {
      await expect(
        osTokenVaultEscrow.connect(dao).updateConfig(0n, newLiqBonusPercent)
      ).to.revertedWithCustomError(osTokenConfig, 'InvalidLiqThresholdPercent')

      await expect(
        osTokenVaultEscrow.connect(dao).updateConfig(maxPercent, newLiqBonusPercent)
      ).to.revertedWithCustomError(osTokenConfig, 'InvalidLiqThresholdPercent')
    })

    it('fails with invalid liqBonusPercent', async () => {
      await expect(
        osTokenVaultEscrow.connect(dao).updateConfig(newLiqThresholdPercent, maxPercent - 1n)
      ).to.revertedWithCustomError(osTokenConfig, 'InvalidLiqBonusPercent')
      await expect(
        osTokenVaultEscrow.connect(dao).updateConfig(parseEther('0.95'), parseEther('1.1'))
      ).to.revertedWithCustomError(osTokenConfig, 'InvalidLiqBonusPercent')
    })

    it('owner can update config', async () => {
      const tx = await osTokenVaultEscrow
        .connect(dao)
        .updateConfig(newLiqThresholdPercent, newLiqBonusPercent)
      await expect(tx)
        .to.emit(osTokenVaultEscrow, 'ConfigUpdated')
        .withArgs(newLiqThresholdPercent, newLiqBonusPercent)
      expect(await osTokenVaultEscrow.liqThresholdPercent()).to.be.eq(newLiqThresholdPercent)
      expect(await osTokenVaultEscrow.liqBonusPercent()).to.be.eq(newLiqBonusPercent)
      await snapshotGasCost(tx)
    })
  })
})
