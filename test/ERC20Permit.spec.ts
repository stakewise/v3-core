import { ethers, network, waffle } from 'hardhat'
import { Wallet } from 'ethers'
import EthereumWallet from 'ethereumjs-wallet'
import { ERC20PermitMock } from '../typechain-types'
import { expect } from './shared/expect'
import { EIP712Domain, MAX_UINT256, PANIC_CODES, Permit } from './shared/constants'
import { domainSeparator, getSignatureFromTypedData, latestTimestamp } from './shared/utils'
import snapshotGasCost from './shared/snapshotGasCost'

describe('ERC20Permit', () => {
  const name = 'Vault Token'
  const symbol = 'VLT'
  const decimals = 18
  const initialSupply = 1000

  let token: ERC20PermitMock
  let initialHolder: Wallet, spender: Wallet, recipient: Wallet, other: Wallet

  let loadFixture: ReturnType<typeof waffle.createFixtureLoader>
  before('create fixture loader', async () => {
    ;[initialHolder, spender, recipient, other] = await (ethers as any).getSigners()
    loadFixture = waffle.createFixtureLoader([initialHolder, spender, recipient, other])
  })

  const fixture = async () => {
    const tokenFactory = await ethers.getContractFactory('ERC20PermitMock')
    const tkn = (await tokenFactory.deploy(name, symbol)) as ERC20PermitMock
    await tkn.mint(initialHolder.address, initialSupply)
    return tkn
  }

  beforeEach('deploy ERC20PermitMock', async () => {
    token = await loadFixture(fixture)
  })

  it('deployment gas', async () => {
    const tokenFactory = await ethers.getContractFactory('ERC20PermitMock')
    const tkn = (await tokenFactory.deploy(name, symbol)) as ERC20PermitMock
    await snapshotGasCost(tkn.deployTransaction)
  })

  it('mint gas', async () => {
    await snapshotGasCost(token.mint(other.address, initialSupply))
  })

  it('has a name', async () => {
    expect(await token.name()).to.eq(name)
  })

  it('has a symbol', async () => {
    expect(await token.symbol()).to.eq(symbol)
  })

  it('has 18 decimals', async () => {
    expect(await token.decimals()).to.eq(decimals)
  })

  describe('total supply', () => {
    it('returns the total amount of tokens', async () => {
      expect(await token.totalSupply()).to.eq(initialSupply)
    })
  })

  describe('balanceOf', () => {
    describe('when the requested account has no tokens', () => {
      it('returns zero', async () => {
        expect(await token.balanceOf(spender.address)).to.eq(0)
      })
    })

    describe('when the requested account has some tokens', () => {
      it('returns the total amount of tokens', async () => {
        expect(await token.balanceOf(initialHolder.address)).to.eq(initialSupply)
      })
    })
  })

  describe('transfer', () => {
    const balance = initialSupply

    it('reverts when the sender does not have enough balance', async () => {
      const amount = balance + 1
      await expect(
        token.connect(initialHolder).transfer(recipient.address, amount)
      ).to.be.revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
    })

    describe('when the sender transfers all balance', () => {
      const amount = initialSupply

      it('transfers the requested amount', async () => {
        const receipt = await token.connect(initialHolder).transfer(recipient.address, amount)
        expect(await token.balanceOf(initialHolder.address)).to.eq(0)
        expect(await token.balanceOf(recipient.address)).to.eq(amount)
        await snapshotGasCost(receipt)
      })

      it('emits a transfer event', async () => {
        await expect(token.connect(initialHolder).transfer(recipient.address, amount))
          .to.emit(token, 'Transfer')
          .withArgs(initialHolder.address, recipient.address, amount)
      })
    })

    describe('when the sender transfers zero tokens', () => {
      const amount = 0
      const balance = initialSupply

      it('transfers the requested amount', async () => {
        const receipt = await token.connect(initialHolder).transfer(recipient.address, amount)
        expect(await token.balanceOf(initialHolder.address)).to.eq(balance)
        expect(await token.balanceOf(recipient.address)).to.eq(0)
        await snapshotGasCost(receipt)
      })

      it('emits a transfer event', async () => {
        await expect(token.connect(initialHolder).transfer(recipient.address, amount))
          .to.emit(token, 'Transfer')
          .withArgs(initialHolder.address, recipient.address, amount)
      })
    })
  })

  describe('transfer from', () => {
    describe('when the spender has enough allowance', () => {
      beforeEach(async () => {
        await token.connect(initialHolder).approve(spender.address, initialSupply)
      })

      describe('when the token owner has enough balance', () => {
        const amount = initialSupply

        it('transfers the requested amount', async () => {
          const receipt = await token
            .connect(spender)
            .transferFrom(initialHolder.address, spender.address, amount)
          expect(await token.balanceOf(initialHolder.address)).to.eq(0)
          expect(await token.balanceOf(spender.address)).to.eq(amount)
          await snapshotGasCost(receipt)
        })

        it('decreases the spender allowance', async () => {
          await token.connect(spender).transferFrom(initialHolder.address, spender.address, amount)
          expect(await token.allowance(initialHolder.address, spender.address)).to.eq(0)
        })

        it('emits a transfer event', async () => {
          await expect(
            token.connect(spender).transferFrom(initialHolder.address, spender.address, amount)
          )
            .emit(token, 'Transfer')
            .withArgs(initialHolder.address, spender.address, amount)
        })
      })

      describe('when the token owner does not have enough balance', () => {
        const amount = initialSupply

        beforeEach('reducing balance', async () => {
          await token.transfer(spender.address, 1, { from: initialHolder.address })
        })

        it('reverts', async () => {
          await expect(
            token.connect(spender).transferFrom(initialHolder.address, spender.address, amount)
          ).to.be.revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
        })
      })
    })

    describe('when the spender does not have enough allowance', () => {
      const allowance = initialSupply - 1

      beforeEach(async () => {
        await token.connect(initialHolder).approve(spender.address, allowance)
      })

      describe('when the token owner has enough balance', () => {
        const amount = initialSupply

        it('reverts', async () => {
          await expect(
            token.connect(spender).transferFrom(initialHolder.address, spender.address, amount)
          ).to.be.revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
        })
      })

      describe('when the token owner does not have enough balance', () => {
        const amount = allowance

        beforeEach('reducing balance', async () => {
          await token.connect(initialHolder).transfer(spender.address, 2)
        })

        it('reverts', async () => {
          await expect(
            token.connect(spender).transferFrom(initialHolder.address, spender.address, amount)
          ).to.be.revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
        })
      })
    })

    describe('when the spender has unlimited allowance', () => {
      beforeEach(async () => {
        await token.connect(initialHolder).approve(spender.address, MAX_UINT256)
      })

      it('does not decrease the spender allowance', async () => {
        const receipt = await token
          .connect(spender)
          .transferFrom(initialHolder.address, spender.address, 1)
        expect(await token.allowance(initialHolder.address, spender.address)).to.eq(MAX_UINT256)
        await snapshotGasCost(receipt)
      })
    })
  })

  describe('approve', () => {
    describe('when the sender has enough balance', () => {
      const amount = initialSupply

      it('emits an approval event', async () => {
        await expect(token.connect(initialHolder).approve(spender.address, amount))
          .emit(token, 'Approval')
          .withArgs(initialHolder.address, spender.address, amount)
      })

      describe('when there was no approved amount before', () => {
        it('approves the requested amount', async () => {
          const receipt = await token.connect(initialHolder).approve(spender.address, amount)
          expect(await token.allowance(initialHolder.address, spender.address)).to.eq(amount)
          await snapshotGasCost(receipt)
        })
      })

      describe('when the spender had an approved amount', () => {
        beforeEach(async () => {
          await token.connect(initialHolder).approve(spender.address, 1)
        })

        it('approves the requested amount and replaces the previous one', async () => {
          const receipt = await token.connect(initialHolder).approve(spender.address, amount)
          expect(await token.allowance(initialHolder.address, spender.address)).to.eq(amount)
          await snapshotGasCost(receipt)
        })
      })
    })

    describe('when the sender does not have enough balance', () => {
      const amount = initialSupply + 1

      it('emits an approval event', async () => {
        await expect(token.connect(initialHolder).approve(spender.address, amount))
          .emit(token, 'Approval')
          .withArgs(initialHolder.address, spender.address, amount)
      })

      describe('when there was no approved amount before', () => {
        it('approves the requested amount', async () => {
          await token.connect(initialHolder).approve(spender.address, amount)
          expect(await token.allowance(initialHolder.address, spender.address)).to.eq(amount)
        })
      })

      describe('when the spender had an approved amount', () => {
        beforeEach(async () => {
          await token.connect(initialHolder).approve(spender.address, 1)
        })

        it('approves the requested amount and replaces the previous one', async () => {
          await token.connect(initialHolder).approve(spender.address, amount)

          expect(await token.allowance(initialHolder.address, spender.address)).to.eq(amount)
        })
      })
    })
  })

  describe('permit', () => {
    const value = 42
    const nonce = 0
    const maxDeadline = MAX_UINT256.toString()
    const chainId = network.config.chainId

    const owner = EthereumWallet.generate()
    const ownerAddress = owner.getChecksumAddressString()
    const ownerPrivateKey = owner.getPrivateKey()

    const buildData = (deadline = maxDeadline) => ({
      primaryType: 'Permit',
      types: { EIP712Domain, Permit },
      domain: {
        name,
        version: '1',
        chainId,
        verifyingContract: token.address,
      },
      message: { owner: ownerAddress, spender: spender.address, value, nonce, deadline },
    })

    it('initial nonce is 0', async () => {
      expect(await token.nonces(ownerAddress)).to.eq(0)
    })

    it('domain separator', async () => {
      expect(await token.DOMAIN_SEPARATOR()).to.equal(
        await domainSeparator(name, '1', chainId, token.address)
      )
    })

    it('accepts owner signature', async () => {
      const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, buildData())

      const receipt = await token.permit(ownerAddress, spender.address, value, maxDeadline, v, r, s)
      await snapshotGasCost(receipt)

      await expect(receipt)
        .to.emit(token, 'Approval')
        .withArgs(ownerAddress, spender.address, value)

      expect(await token.nonces(ownerAddress)).to.eq('1')
      expect(await token.allowance(ownerAddress, spender.address)).to.eq(value)
    })

    it('rejects reused signature', async () => {
      const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, buildData())

      await token.permit(ownerAddress, spender.address, value, maxDeadline, v, r, s)

      await expect(
        token.permit(initialHolder.address, spender.address, value, maxDeadline, v, r, s)
      ).to.be.revertedWith('PermitInvalidSigner()')
    })

    it('rejects other signature', async () => {
      const otherWallet = EthereumWallet.generate()
      const data = buildData()
      const { v, r, s } = getSignatureFromTypedData(otherWallet.getPrivateKey(), data)

      await expect(
        token.permit(ownerAddress, spender.address, value, maxDeadline, v, r, s)
      ).to.be.revertedWith('PermitInvalidSigner()')
    })

    it('rejects expired permit', async () => {
      const deadline = (await latestTimestamp()).sub(500).toString()
      const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, buildData(deadline))

      await expect(
        token.permit(ownerAddress, spender.address, value, deadline, v, r, s)
      ).to.be.revertedWith('PermitDeadlineExpired()')
    })
  })
})
