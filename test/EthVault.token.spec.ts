import { ethers, network, waffle } from 'hardhat'
import { Wallet } from 'ethers'
import { arrayify, parseEther } from 'ethers/lib/utils'
import EthereumWallet from 'ethereumjs-wallet'
import { EthVault } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import { expect } from './shared/expect'
import { EIP712Domain, MAX_UINT256, PANIC_CODES, PermitSig } from './shared/constants'
import { domainSeparator, getSignatureFromTypedData, latestTimestamp } from './shared/utils'
import snapshotGasCost from './shared/snapshotGasCost'
import { ethVaultFixture } from './shared/fixtures'

const createFixtureLoader = waffle.createFixtureLoader

describe('EthVault - token', () => {
  const maxTotalAssets = parseEther('1000')
  const feePercent = 1000
  const vaultName = 'SW ETH Vault'
  const vaultSymbol = 'SW-ETH-1'
  const validatorsRoot = '0x059a8487a1ce461e9670c4646ef85164ae8791613866d28c972fb351dc45c606'
  const validatorsIpfsHash = '/ipfs/QmfPnyNojfyqoi9yqS3jMp16GGiTQee4bdCXJC64KqvTgc'
  const initialSupply = 1000

  let vault: EthVault
  let admin: Wallet, dao: Wallet, initialHolder: Wallet, spender: Wallet, recipient: Wallet

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createVault']

  before('create fixture loader', async () => {
    ;[admin, dao, initialHolder, spender, recipient] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([dao])
  })

  beforeEach('deploy fixture', async () => {
    ;({ createVault } = await loadFixture(ethVaultFixture))
    vault = await createVault(
      admin,
      maxTotalAssets,
      validatorsRoot,
      feePercent,
      vaultName,
      vaultSymbol,
      validatorsIpfsHash
    )
    await vault.connect(initialHolder).deposit(initialHolder.address, { value: initialSupply })
  })

  it('has a name', async () => {
    expect(await vault.name()).to.eq(vaultName)
  })

  it('has a symbol', async () => {
    expect(await vault.symbol()).to.eq(vaultSymbol)
  })

  it('has 18 decimals', async () => {
    expect(await vault.decimals()).to.eq(18)
  })

  it('fails to deploy with invalid name length', async () => {
    await expect(
      createVault(
        admin,
        maxTotalAssets,
        validatorsRoot,
        feePercent,
        'a'.repeat(31),
        vaultSymbol,
        validatorsIpfsHash
      )
    ).to.be.revertedWith('InvalidInitArgs()')
  })

  it('fails to deploy with invalid symbol length', async () => {
    await expect(
      createVault(
        admin,
        maxTotalAssets,
        validatorsRoot,
        feePercent,
        vaultName,
        'a'.repeat(21),
        validatorsIpfsHash
      )
    ).to.be.revertedWith('InvalidInitArgs()')
  })

  describe('total supply', () => {
    it('returns the total amount of tokens', async () => {
      expect(await vault.totalSupply()).to.eq(initialSupply)
    })
  })

  describe('balanceOf', () => {
    describe('when the requested account has no tokens', () => {
      it('returns zero', async () => {
        expect(await vault.balanceOf(spender.address)).to.eq(0)
      })
    })

    describe('when the requested account has some tokens', () => {
      it('returns the total amount of tokens', async () => {
        expect(await vault.balanceOf(initialHolder.address)).to.eq(initialSupply)
      })
    })
  })

  describe('transfer', () => {
    const balance = initialSupply

    it('reverts when the sender does not have enough balance', async () => {
      const amount = balance + 1
      await expect(
        vault.connect(initialHolder).transfer(recipient.address, amount)
      ).to.be.revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
    })

    describe('when the sender transfers all balance', () => {
      const amount = initialSupply

      it('transfers the requested amount', async () => {
        const receipt = await vault.connect(initialHolder).transfer(recipient.address, amount)
        expect(await vault.balanceOf(initialHolder.address)).to.eq(0)
        expect(await vault.balanceOf(recipient.address)).to.eq(amount)
        await snapshotGasCost(receipt)
      })

      it('emits a transfer event', async () => {
        await expect(vault.connect(initialHolder).transfer(recipient.address, amount))
          .to.emit(vault, 'Transfer')
          .withArgs(initialHolder.address, recipient.address, amount)
      })
    })

    describe('when the sender transfers zero tokens', () => {
      const amount = 0
      const balance = initialSupply

      it('transfers the requested amount', async () => {
        const receipt = await vault.connect(initialHolder).transfer(recipient.address, amount)
        expect(await vault.balanceOf(initialHolder.address)).to.eq(balance)
        expect(await vault.balanceOf(recipient.address)).to.eq(0)
        await snapshotGasCost(receipt)
      })

      it('emits a transfer event', async () => {
        await expect(vault.connect(initialHolder).transfer(recipient.address, amount))
          .to.emit(vault, 'Transfer')
          .withArgs(initialHolder.address, recipient.address, amount)
      })
    })
  })

  describe('transfer from', () => {
    describe('when the spender has enough allowance', () => {
      beforeEach(async () => {
        await vault.connect(initialHolder).approve(spender.address, initialSupply)
      })

      describe('when the token owner has enough balance', () => {
        const amount = initialSupply

        it('transfers the requested amount', async () => {
          const receipt = await vault
            .connect(spender)
            .transferFrom(initialHolder.address, spender.address, amount)
          expect(await vault.balanceOf(initialHolder.address)).to.eq(0)
          expect(await vault.balanceOf(spender.address)).to.eq(amount)
          await snapshotGasCost(receipt)
        })

        it('decreases the spender allowance', async () => {
          await vault.connect(spender).transferFrom(initialHolder.address, spender.address, amount)
          expect(await vault.allowance(initialHolder.address, spender.address)).to.eq(0)
        })

        it('emits a transfer event', async () => {
          await expect(
            vault.connect(spender).transferFrom(initialHolder.address, spender.address, amount)
          )
            .emit(vault, 'Transfer')
            .withArgs(initialHolder.address, spender.address, amount)
        })
      })

      describe('when the token owner does not have enough balance', () => {
        const amount = initialSupply

        beforeEach('reducing balance', async () => {
          await vault.connect(initialHolder).transfer(spender.address, 1)
        })

        it('reverts', async () => {
          await expect(
            vault.connect(spender).transferFrom(initialHolder.address, spender.address, amount)
          ).to.be.revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
        })
      })
    })

    describe('when the spender does not have enough allowance', () => {
      const allowance = initialSupply - 1

      beforeEach(async () => {
        await vault.connect(initialHolder).approve(spender.address, allowance)
      })

      describe('when the token owner has enough balance', () => {
        const amount = initialSupply

        it('reverts', async () => {
          await expect(
            vault.connect(spender).transferFrom(initialHolder.address, spender.address, amount)
          ).to.be.revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
        })
      })

      describe('when the token owner does not have enough balance', () => {
        const amount = allowance

        beforeEach('reducing balance', async () => {
          await vault.connect(initialHolder).transfer(spender.address, 2)
        })

        it('reverts', async () => {
          await expect(
            vault.connect(spender).transferFrom(initialHolder.address, spender.address, amount)
          ).to.be.revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
        })
      })
    })

    describe('when the spender has unlimited allowance', () => {
      beforeEach(async () => {
        await vault.connect(initialHolder).approve(spender.address, MAX_UINT256)
      })

      it('does not decrease the spender allowance', async () => {
        const receipt = await vault
          .connect(spender)
          .transferFrom(initialHolder.address, spender.address, 1)
        expect(await vault.allowance(initialHolder.address, spender.address)).to.eq(MAX_UINT256)
        await snapshotGasCost(receipt)
      })
    })
  })

  describe('approve', () => {
    describe('when the sender has enough balance', () => {
      const amount = initialSupply

      it('emits an approval event', async () => {
        await expect(vault.connect(initialHolder).approve(spender.address, amount))
          .emit(vault, 'Approval')
          .withArgs(initialHolder.address, spender.address, amount)
      })

      describe('when there was no approved amount before', () => {
        it('approves the requested amount', async () => {
          const receipt = await vault.connect(initialHolder).approve(spender.address, amount)
          expect(await vault.allowance(initialHolder.address, spender.address)).to.eq(amount)
          await snapshotGasCost(receipt)
        })
      })

      describe('when the spender had an approved amount', () => {
        beforeEach(async () => {
          await vault.connect(initialHolder).approve(spender.address, 1)
        })

        it('approves the requested amount and replaces the previous one', async () => {
          const receipt = await vault.connect(initialHolder).approve(spender.address, amount)
          expect(await vault.allowance(initialHolder.address, spender.address)).to.eq(amount)
          await snapshotGasCost(receipt)
        })
      })
    })

    describe('when the sender does not have enough balance', () => {
      const amount = initialSupply + 1

      it('emits an approval event', async () => {
        await expect(vault.connect(initialHolder).approve(spender.address, amount))
          .emit(vault, 'Approval')
          .withArgs(initialHolder.address, spender.address, amount)
      })

      describe('when there was no approved amount before', () => {
        it('approves the requested amount', async () => {
          await vault.connect(initialHolder).approve(spender.address, amount)
          expect(await vault.allowance(initialHolder.address, spender.address)).to.eq(amount)
        })
      })

      describe('when the spender had an approved amount', () => {
        beforeEach(async () => {
          await vault.connect(initialHolder).approve(spender.address, 1)
        })

        it('approves the requested amount and replaces the previous one', async () => {
          await vault.connect(initialHolder).approve(spender.address, amount)

          expect(await vault.allowance(initialHolder.address, spender.address)).to.eq(amount)
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
      Buffer.from(arrayify('0x35a1c4d02b06d93778758410e5c09e010760268cf98b1af33c2d0646f27a8b70'))
    )
    const ownerAddress = owner.getChecksumAddressString()
    const ownerPrivateKey = owner.getPrivateKey()

    const buildData = (deadline = maxDeadline) => ({
      primaryType: 'Permit',
      types: { EIP712Domain, Permit: PermitSig },
      domain: {
        name: vaultName,
        version: '1',
        chainId,
        verifyingContract: vault.address,
      },
      message: { owner: ownerAddress, spender: spender.address, value, nonce, deadline },
    })

    it('initial nonce is 0', async () => {
      expect(await vault.nonces(ownerAddress)).to.eq(0)
    })

    it('domain separator', async () => {
      expect(await vault.DOMAIN_SEPARATOR()).to.equal(
        await domainSeparator(vaultName, '1', chainId, vault.address)
      )
    })

    it('accepts owner signature', async () => {
      const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, buildData())

      const receipt = await vault.permit(ownerAddress, spender.address, value, maxDeadline, v, r, s)
      await snapshotGasCost(receipt)

      await expect(receipt)
        .to.emit(vault, 'Approval')
        .withArgs(ownerAddress, spender.address, value)

      expect(await vault.nonces(ownerAddress)).to.eq('1')
      expect(await vault.allowance(ownerAddress, spender.address)).to.eq(value)
    })

    it('rejects reused signature', async () => {
      const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, buildData())

      await vault.permit(ownerAddress, spender.address, value, maxDeadline, v, r, s)

      await expect(
        vault.permit(initialHolder.address, spender.address, value, maxDeadline, v, r, s)
      ).to.be.revertedWith('PermitInvalidSigner()')
    })

    it('rejects other signature', async () => {
      const otherWallet = EthereumWallet.generate()
      const data = buildData()
      const { v, r, s } = getSignatureFromTypedData(otherWallet.getPrivateKey(), data)

      await expect(
        vault.permit(ownerAddress, spender.address, value, maxDeadline, v, r, s)
      ).to.be.revertedWith('PermitInvalidSigner()')
    })

    it('rejects expired permit', async () => {
      const deadline = (await latestTimestamp()).sub(500).toString()
      const { v, r, s } = getSignatureFromTypedData(ownerPrivateKey, buildData(deadline))

      await expect(
        vault.permit(ownerAddress, spender.address, value, deadline, v, r, s)
      ).to.be.revertedWith('PermitDeadlineExpired()')
    })
  })
})
