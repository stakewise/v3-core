import { ethers, network } from 'hardhat'
import { Wallet } from 'ethers'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { OsTokenVaultController, OsToken } from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import {
  EIP712Domain,
  MAX_UINT256,
  ONE_DAY,
  OSTOKEN_NAME,
  OSTOKEN_SYMBOL,
  PermitSig,
  ZERO_ADDRESS,
} from './shared/constants'
import { collateralizeEthVault } from './shared/rewards'
import EthereumWallet from 'ethereumjs-wallet'
import {
  domainSeparator,
  getSignatureFromTypedData,
  increaseTime,
  getLatestBlockTimestamp,
} from './shared/utils'

describe('OsToken', () => {
  const assets = ethers.parseEther('2')
  const initialHolderShares = 1000n
  let initialSupply: bigint
  let initialHolder: Wallet, spender: Wallet, admin: Wallet, dao: Wallet, recipient: Wallet
  let osTokenVaultController: OsTokenVaultController, osToken: OsToken

  before('create fixture loader', async () => {
    ;[dao, initialHolder, admin, spender, recipient] = await (ethers as any).getSigners()
  })

  beforeEach('deploy fixture', async () => {
    const fixture = await loadFixture(ethVaultFixture)
    const vaultParams = {
      capacity: ethers.parseEther('1000'),
      feePercent: 1000,
      metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u',
    }
    osTokenVaultController = fixture.osTokenVaultController
    osToken = fixture.osToken
    const vault = await fixture.createEthVault(admin, vaultParams)

    // collateralize vault
    await collateralizeEthVault(vault, fixture.keeper, fixture.validatorsRegistry, admin)
    await vault
      .connect(initialHolder)
      .deposit(initialHolder.address, ZERO_ADDRESS, { value: assets })
    await vault
      .connect(initialHolder)
      .mintOsToken(initialHolder.address, initialHolderShares, ZERO_ADDRESS)
    initialSupply = await osToken.totalSupply()
  })

  describe('capacity', () => {
    it('not owner cannot change', async () => {
      await expect(
        osTokenVaultController.connect(initialHolder).setCapacity(0)
      ).to.be.revertedWithCustomError(osToken, 'OwnableUnauthorizedAccount')
    })

    it('owner can change', async () => {
      const receipt = await osTokenVaultController.connect(dao).setCapacity(0)
      await expect(receipt).to.emit(osTokenVaultController, 'CapacityUpdated').withArgs(0)
      expect(await osTokenVaultController.capacity()).to.eq(0)
      await snapshotGasCost(receipt)
    })
  })

  describe('treasury', () => {
    it('not owner cannot change', async () => {
      await expect(
        osTokenVaultController.connect(initialHolder).setTreasury(dao.address)
      ).to.be.revertedWithCustomError(osToken, 'OwnableUnauthorizedAccount')
    })

    it('cannot set to zero address', async () => {
      await expect(
        osTokenVaultController.connect(dao).setTreasury(ZERO_ADDRESS)
      ).to.be.revertedWithCustomError(osToken, 'ZeroAddress')
    })

    it('owner can change', async () => {
      const receipt = await osTokenVaultController.connect(dao).setTreasury(dao.address)
      await expect(receipt).to.emit(osTokenVaultController, 'TreasuryUpdated').withArgs(dao.address)
      expect(await osTokenVaultController.treasury()).to.eq(dao.address)
      await snapshotGasCost(receipt)
    })
  })

  describe('controllers', () => {
    it('not owner cannot change', async () => {
      await expect(
        osToken.connect(initialHolder).setController(dao.address, true)
      ).to.be.revertedWithCustomError(osToken, 'OwnableUnauthorizedAccount')
    })

    it('cannot set to zero address', async () => {
      await expect(
        osToken.connect(dao).setController(ZERO_ADDRESS, true)
      ).to.be.revertedWithCustomError(osToken, 'ZeroAddress')
    })

    it('owner can change', async () => {
      let receipt = await osToken.connect(dao).setController(dao.address, true)
      await expect(receipt).to.emit(osToken, 'ControllerUpdated').withArgs(dao.address, true)
      expect(await osToken.controllers(dao.address)).to.eq(true)
      await snapshotGasCost(receipt)

      receipt = await osToken.connect(dao).setController(dao.address, false)
      await expect(receipt).to.emit(osToken, 'ControllerUpdated').withArgs(dao.address, false)
      expect(await osToken.controllers(dao.address)).to.eq(false)
      await snapshotGasCost(receipt)
    })

    it('not controller cannot mint', async () => {
      await expect(
        osToken.connect(initialHolder).mint(dao.address, 1)
      ).to.be.revertedWithCustomError(osToken, 'AccessDenied')
    })

    it('controller can mint', async () => {
      await osToken.connect(dao).setController(initialHolder.address, true)
      const receipt = await osToken.connect(initialHolder).mint(recipient.address, 1)
      await expect(receipt)
        .to.emit(osToken, 'Transfer')
        .withArgs(ZERO_ADDRESS, recipient.address, 1)
      expect(await osToken.balanceOf(recipient.address)).to.eq(1)
    })

    it('not controller cannot burn', async () => {
      await expect(
        osToken.connect(initialHolder).burn(dao.address, 1)
      ).to.be.revertedWithCustomError(osToken, 'AccessDenied')
    })

    it('controller can burn', async () => {
      await osToken.connect(dao).setController(initialHolder.address, true)
      await osToken.connect(initialHolder).mint(recipient.address, 1)
      const receipt = await osToken.connect(initialHolder).burn(recipient.address, 1)
      await expect(receipt)
        .to.emit(osToken, 'Transfer')
        .withArgs(recipient.address, ZERO_ADDRESS, 1)
      expect(await osToken.balanceOf(recipient.address)).to.eq(0)
    })
  })

  describe('fee percent', () => {
    it('not owner cannot change', async () => {
      await expect(
        osTokenVaultController.connect(initialHolder).setFeePercent(100)
      ).to.be.revertedWithCustomError(osToken, 'OwnableUnauthorizedAccount')
    })

    it('cannot set to more than 100%', async () => {
      await expect(
        osTokenVaultController.connect(dao).setFeePercent(10001)
      ).to.be.revertedWithCustomError(osTokenVaultController, 'InvalidFeePercent')
    })

    it('owner can change', async () => {
      await increaseTime(ONE_DAY * 1000)
      const receipt = await osTokenVaultController.connect(dao).setFeePercent(100)
      await expect(receipt).to.emit(osTokenVaultController, 'FeePercentUpdated').withArgs(100)
      await expect(receipt).to.emit(osTokenVaultController, 'StateUpdated')
      expect(await osTokenVaultController.feePercent()).to.eq(100)
      await snapshotGasCost(receipt)
    })
  })

  describe('keeper', () => {
    it('not owner cannot change', async () => {
      await expect(
        osTokenVaultController.connect(initialHolder).setKeeper(dao.address)
      ).to.be.revertedWithCustomError(osTokenVaultController, 'OwnableUnauthorizedAccount')
    })

    it('cannot set to zero address', async () => {
      await expect(
        osTokenVaultController.connect(dao).setKeeper(ZERO_ADDRESS)
      ).to.be.revertedWithCustomError(osTokenVaultController, 'ZeroAddress')
    })

    it('owner can change', async () => {
      const receipt = await osTokenVaultController.connect(dao).setKeeper(dao.address)
      await expect(receipt).to.emit(osTokenVaultController, 'KeeperUpdated').withArgs(dao.address)
      expect(await osTokenVaultController.keeper()).to.eq(dao.address)
      await snapshotGasCost(receipt)
    })
  })

  describe('avg reward per second', () => {
    it('not owner cannot change', async () => {
      await expect(
        osTokenVaultController.connect(dao).setAvgRewardPerSecond(0)
      ).to.be.revertedWithCustomError(osTokenVaultController, 'AccessDenied')
    })
  })

  it('has a name', async () => {
    expect(await osToken.name()).to.eq(OSTOKEN_NAME)
  })

  it('has a symbol', async () => {
    expect(await osToken.symbol()).to.eq(OSTOKEN_SYMBOL)
  })

  it('has 18 decimals', async () => {
    expect(await osToken.decimals()).to.eq(18)
  })

  describe('total supply', () => {
    it('returns the total amount of tokens', async () => {
      expect(await osToken.totalSupply()).to.eq(initialSupply)
      expect(await osTokenVaultController.totalShares()).to.eq(initialSupply)
    })
  })

  describe('balanceOf', () => {
    describe('when the requested account has no tokens', () => {
      it('returns zero', async () => {
        expect(await osToken.balanceOf(spender.address)).to.eq(0)
      })
    })

    describe('when the requested account has some tokens', () => {
      it('returns the total amount of tokens', async () => {
        expect(await osToken.balanceOf(initialHolder.address)).to.eq(initialHolderShares)
      })
    })
  })

  describe('transfer', () => {
    const balance = initialHolderShares

    it('reverts when the sender does not have enough balance', async () => {
      const amount = balance + 1n
      await expect(
        osToken.connect(initialHolder).transfer(recipient.address, amount)
      ).to.be.revertedWithCustomError(osToken, 'ERC20InsufficientBalance')
    })

    it('reverts with zero address recipient', async () => {
      await expect(
        osToken.connect(initialHolder).transfer(ZERO_ADDRESS, balance)
      ).to.be.revertedWithCustomError(osToken, 'ERC20InvalidReceiver')
    })

    describe('when the sender transfers all balance', () => {
      const amount = initialHolderShares

      it('transfers the requested amount', async () => {
        const receipt = await osToken.connect(initialHolder).transfer(recipient.address, amount)
        expect(await osToken.balanceOf(initialHolder.address)).to.eq(0)
        expect(await osToken.balanceOf(recipient.address)).to.eq(amount)
        await snapshotGasCost(receipt)
      })

      it('emits a transfer event', async () => {
        await expect(osToken.connect(initialHolder).transfer(recipient.address, amount))
          .to.emit(osToken, 'Transfer')
          .withArgs(initialHolder.address, recipient.address, amount)
      })
    })

    describe('when the sender transfers zero tokens', () => {
      const amount = 0
      const balance = initialHolderShares

      it('transfers the requested amount', async () => {
        const receipt = await osToken.connect(initialHolder).transfer(recipient.address, amount)
        expect(await osToken.balanceOf(initialHolder.address)).to.eq(balance)
        expect(await osToken.balanceOf(recipient.address)).to.eq(0)
        await snapshotGasCost(receipt)
      })

      it('emits a transfer event', async () => {
        await expect(osToken.connect(initialHolder).transfer(recipient.address, amount))
          .to.emit(osToken, 'Transfer')
          .withArgs(initialHolder.address, recipient.address, amount)
      })
    })
  })

  describe('transfer from', () => {
    describe('when the spender has enough allowance', () => {
      beforeEach(async () => {
        await osToken.connect(initialHolder).approve(spender.address, initialHolderShares)
      })

      describe('when the token owner has enough balance', () => {
        const amount = initialHolderShares

        it('transfers the requested amount', async () => {
          const receipt = await osToken
            .connect(spender)
            .transferFrom(initialHolder.address, spender.address, amount)
          expect(await osToken.balanceOf(initialHolder.address)).to.eq(0)
          expect(await osToken.balanceOf(spender.address)).to.eq(amount)
          await snapshotGasCost(receipt)
        })

        it('decreases the spender allowance', async () => {
          await osToken
            .connect(spender)
            .transferFrom(initialHolder.address, spender.address, amount)
          expect(await osToken.allowance(initialHolder.address, spender.address)).to.eq(0)
        })

        it('emits a transfer event', async () => {
          await expect(
            osToken.connect(spender).transferFrom(initialHolder.address, spender.address, amount)
          )
            .emit(osToken, 'Transfer')
            .withArgs(initialHolder.address, spender.address, amount)
        })
      })

      describe('when the token owner does not have enough balance', () => {
        const amount = initialHolderShares

        beforeEach('reducing balance', async () => {
          await osToken.connect(initialHolder).transfer(spender.address, 1)
        })

        it('reverts', async () => {
          await expect(
            osToken.connect(spender).transferFrom(initialHolder.address, spender.address, amount)
          ).to.be.revertedWithCustomError(osToken, 'ERC20InsufficientBalance')
        })
      })
    })

    describe('when the spender does not have enough allowance', () => {
      const allowance = initialHolderShares - 1n

      beforeEach(async () => {
        await osToken.connect(initialHolder).approve(spender.address, allowance)
      })

      describe('when the token owner has enough balance', () => {
        const amount = initialHolderShares

        it('reverts', async () => {
          await expect(
            osToken.connect(spender).transferFrom(initialHolder.address, spender.address, amount)
          ).to.be.revertedWithCustomError(osToken, 'ERC20InsufficientAllowance')
        })
      })

      describe('when the token owner does not have enough balance', () => {
        const amount = allowance

        beforeEach('reducing balance', async () => {
          await osToken.connect(initialHolder).transfer(spender.address, 2)
        })

        it('reverts', async () => {
          await expect(
            osToken.connect(spender).transferFrom(initialHolder.address, spender.address, amount)
          ).to.be.revertedWithCustomError(osToken, 'ERC20InsufficientBalance')
        })
      })
    })

    describe('when the spender has unlimited allowance', () => {
      beforeEach(async () => {
        await osToken.connect(initialHolder).approve(spender.address, MAX_UINT256)
      })

      it('does not decrease the spender allowance', async () => {
        const receipt = await osToken
          .connect(spender)
          .transferFrom(initialHolder.address, spender.address, 1)
        expect(await osToken.allowance(initialHolder.address, spender.address)).to.eq(MAX_UINT256)
        await snapshotGasCost(receipt)
      })
    })
  })

  describe('approve', () => {
    it('fails to approve zero address', async () => {
      const amount = ethers.parseEther('1')
      await expect(
        osToken.connect(initialHolder).approve(ZERO_ADDRESS, amount)
      ).to.be.revertedWithCustomError(osToken, 'ERC20InvalidSpender')
    })

    describe('when the sender has enough balance', () => {
      const amount = initialHolderShares

      it('emits an approval event', async () => {
        await expect(osToken.connect(initialHolder).approve(spender.address, amount))
          .emit(osToken, 'Approval')
          .withArgs(initialHolder.address, spender.address, amount)
      })

      describe('when there was no approved amount before', () => {
        it('approves the requested amount', async () => {
          const receipt = await osToken.connect(initialHolder).approve(spender.address, amount)
          expect(await osToken.allowance(initialHolder.address, spender.address)).to.eq(amount)
          await snapshotGasCost(receipt)
        })
      })

      describe('when the spender had an approved amount', () => {
        beforeEach(async () => {
          await osToken.connect(initialHolder).approve(spender.address, 1)
        })

        it('approves the requested amount and replaces the previous one', async () => {
          const receipt = await osToken.connect(initialHolder).approve(spender.address, amount)
          expect(await osToken.allowance(initialHolder.address, spender.address)).to.eq(amount)
          await snapshotGasCost(receipt)
        })
      })
    })

    describe('when the sender does not have enough balance', () => {
      const amount = initialHolderShares + 1n

      it('emits an approval event', async () => {
        await expect(osToken.connect(initialHolder).approve(spender.address, amount))
          .emit(osToken, 'Approval')
          .withArgs(initialHolder.address, spender.address, amount)
      })

      describe('when there was no approved amount before', () => {
        it('approves the requested amount', async () => {
          await osToken.connect(initialHolder).approve(spender.address, amount)
          expect(await osToken.allowance(initialHolder.address, spender.address)).to.eq(amount)
        })
      })

      describe('when the spender had an approved amount', () => {
        beforeEach(async () => {
          await osToken.connect(initialHolder).approve(spender.address, 1)
        })

        it('approves the requested amount and replaces the previous one', async () => {
          await osToken.connect(initialHolder).approve(spender.address, amount)

          expect(await osToken.allowance(initialHolder.address, spender.address)).to.eq(amount)
        })
      })
    })
  })

  describe('permit', () => {
    const value = 42
    const nonce = 0
    const maxDeadline = MAX_UINT256.toString()
    const chainId = network.config.chainId

    const owner = new EthereumWallet(
      Buffer.from(
        ethers.getBytes('0x35a1c4d02b06d93778758410e5c09e010760268cf98b1af33c2d0646f27a8b70')
      )
    )
    const ownerAddress = owner.getChecksumAddressString()
    const ownerPrivateKey = owner.getPrivateKey()

    const buildData = async (deadline = maxDeadline, spender) => ({
      primaryType: 'Permit',
      types: { EIP712Domain, Permit: PermitSig },
      domain: {
        name: OSTOKEN_NAME,
        version: '1',
        chainId,
        verifyingContract: await osToken.getAddress(),
      },
      message: { owner: ownerAddress, spender, value, nonce, deadline },
    })

    it('initial nonce is 0', async () => {
      expect(await osToken.nonces(ownerAddress)).to.eq(0)
    })

    it('domain separator', async () => {
      expect(await osToken.DOMAIN_SEPARATOR()).to.equal(
        await domainSeparator(OSTOKEN_NAME, '1', chainId, await osToken.getAddress())
      )
    })

    it('accepts owner signature', async () => {
      const { v, r, s } = getSignatureFromTypedData(
        ownerPrivateKey,
        await buildData(maxDeadline, spender.address)
      )

      const receipt = await osToken.permit(
        ownerAddress,
        spender.address,
        value,
        maxDeadline,
        v,
        r,
        s
      )
      await snapshotGasCost(receipt)

      await expect(receipt)
        .to.emit(osToken, 'Approval')
        .withArgs(ownerAddress, spender.address, value)

      expect(await osToken.nonces(ownerAddress)).to.eq('1')
      expect(await osToken.allowance(ownerAddress, spender.address)).to.eq(value)
    })

    it('rejects reused signature', async () => {
      const { v, r, s } = getSignatureFromTypedData(
        ownerPrivateKey,
        await buildData(maxDeadline, spender.address)
      )

      await osToken.permit(ownerAddress, spender.address, value, maxDeadline, v, r, s)

      await expect(
        osToken.permit(initialHolder.address, spender.address, value, maxDeadline, v, r, s)
      ).to.be.revertedWithCustomError(osToken, 'ERC2612InvalidSigner')
    })

    it('rejects other signature', async () => {
      const otherWallet = EthereumWallet.generate()
      const data = await buildData(maxDeadline, spender.address)
      const { v, r, s } = getSignatureFromTypedData(otherWallet.getPrivateKey(), data)

      await expect(
        osToken.permit(ownerAddress, spender.address, value, maxDeadline, v, r, s)
      ).to.be.revertedWithCustomError(osToken, 'ERC2612InvalidSigner')
    })

    it('rejects expired permit', async () => {
      const deadline = ((await getLatestBlockTimestamp()) - 500).toString()
      const { v, r, s } = getSignatureFromTypedData(
        ownerPrivateKey,
        await buildData(deadline, spender.address)
      )

      await expect(
        osToken.permit(ownerAddress, spender.address, value, deadline, v, r, s)
      ).to.be.revertedWithCustomError(osToken, 'ERC2612ExpiredSignature')
    })

    it('rejects zero address', async () => {
      const deadline = ((await getLatestBlockTimestamp()) - 500).toString()
      const { v, r, s } = getSignatureFromTypedData(
        ownerPrivateKey,
        await buildData(deadline, ZERO_ADDRESS)
      )

      await expect(
        osToken.permit(ownerAddress, ZERO_ADDRESS, value, deadline, v, r, s)
      ).to.be.revertedWithCustomError(osToken, 'ERC2612ExpiredSignature')
    })
  })
})
