import { ethers, network } from 'hardhat'
import { Wallet } from 'ethers'
import EthereumWallet from 'ethereumjs-wallet'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { EthErc20Vault } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import { expect } from './shared/expect'
import {
  EIP712Domain,
  MAX_UINT256,
  PANIC_CODES,
  PermitSig,
  SECURITY_DEPOSIT,
  ZERO_ADDRESS,
} from './shared/constants'
import { domainSeparator, getLatestBlockTimestamp, getSignatureFromTypedData } from './shared/utils'
import snapshotGasCost from './shared/snapshotGasCost'
import { ethVaultFixture } from './shared/fixtures'

describe('EthVault - token', () => {
  const capacity = ethers.parseEther('1000')
  const feePercent = 1000
  const name = 'SW ETH Vault'
  const symbol = 'SW-ETH-1'
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  const initialSupply = 1000n

  let vault: EthErc20Vault
  let admin: Wallet, initialHolder: Wallet, spender: Wallet, recipient: Wallet

  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createEthErc20Vault']

  before('create fixture loader', async () => {
    ;[admin, initialHolder, spender, recipient] = (await (ethers as any).getSigners()).slice(1, 5)
  })

  beforeEach('deploy fixture', async () => {
    ;({ createEthErc20Vault: createVault } = await loadFixture(ethVaultFixture))
    vault = await createVault(admin, {
      capacity,
      feePercent,
      name,
      symbol,
      metadataIpfsHash,
    })
    await vault
      .connect(initialHolder)
      .deposit(initialHolder.address, ZERO_ADDRESS, { value: initialSupply })
  })

  it('has a name', async () => {
    expect(await vault.name()).to.eq(name)
  })

  it('has a symbol', async () => {
    expect(await vault.symbol()).to.eq(symbol)
  })

  it('has 18 decimals', async () => {
    expect(await vault.decimals()).to.eq(18)
  })

  it('fails to deploy with invalid name length', async () => {
    await expect(
      createVault(admin, {
        capacity,
        feePercent,
        name: 'a'.repeat(31),
        symbol,
        metadataIpfsHash,
      })
    ).to.be.revertedWithCustomError(vault, 'InvalidTokenMeta')
  })

  it('fails to deploy with zero capacity', async () => {
    await expect(
      createVault(admin, {
        capacity: 0n,
        feePercent,
        name,
        symbol,
        metadataIpfsHash,
      })
    ).to.be.revertedWithCustomError(vault, 'InvalidCapacity')
  })

  it('fails to deploy with capacity less than validator deposit amount', async () => {
    await expect(
      createVault(admin, {
        capacity: ethers.parseEther('31'),
        feePercent,
        name,
        symbol,
        metadataIpfsHash,
      })
    ).to.be.revertedWithCustomError(vault, 'InvalidCapacity')
  })

  it('fails to deploy with invalid symbol length', async () => {
    await expect(
      createVault(admin, {
        capacity,
        feePercent,
        name,
        symbol: 'a'.repeat(21),
        metadataIpfsHash,
      })
    ).to.be.revertedWithCustomError(vault, 'InvalidTokenMeta')
  })

  describe('total supply', () => {
    it('returns the total amount of tokens', async () => {
      expect(await vault.totalSupply()).to.eq(SECURITY_DEPOSIT + initialSupply)
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
      const amount = balance + 1n
      await expect(
        vault.connect(initialHolder).transfer(recipient.address, amount)
      ).to.be.revertedWithPanic(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
    })

    it('reverts with zero address recipient', async () => {
      await expect(
        vault.connect(initialHolder).transfer(ZERO_ADDRESS, balance)
      ).to.be.revertedWithCustomError(vault, 'ZeroAddress')
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
          ).to.be.revertedWithPanic(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
        })
      })
    })

    describe('when the spender does not have enough allowance', () => {
      const allowance = initialSupply - 1n

      beforeEach(async () => {
        await vault.connect(initialHolder).approve(spender.address, allowance)
      })

      describe('when the token owner has enough balance', () => {
        const amount = initialSupply

        it('reverts', async () => {
          await expect(
            vault.connect(spender).transferFrom(initialHolder.address, spender.address, amount)
          ).to.be.revertedWithPanic(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
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
          ).to.be.revertedWithPanic(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
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
    it('fails to approve zero address', async () => {
      const amount = ethers.parseEther('1')
      await expect(
        vault.connect(initialHolder).approve(ZERO_ADDRESS, amount)
      ).to.be.revertedWithCustomError(vault, 'ZeroAddress')
    })

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
      const amount = initialSupply + 1n

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
        name,
        version: '1',
        chainId,
        verifyingContract: await vault.getAddress(),
      },
      message: { owner: ownerAddress, spender, value, nonce, deadline },
    })

    it('initial nonce is 0', async () => {
      expect(await vault.nonces(ownerAddress)).to.eq(0)
    })

    it('domain separator', async () => {
      expect(await vault.DOMAIN_SEPARATOR()).to.equal(
        await domainSeparator(name, '1', chainId, await vault.getAddress())
      )
    })

    it('accepts owner signature', async () => {
      const { v, r, s } = getSignatureFromTypedData(
        ownerPrivateKey,
        await buildData(maxDeadline, spender.address)
      )

      const receipt = await vault.permit(ownerAddress, spender.address, value, maxDeadline, v, r, s)
      await snapshotGasCost(receipt)

      await expect(receipt)
        .to.emit(vault, 'Approval')
        .withArgs(ownerAddress, spender.address, value)

      expect(await vault.nonces(ownerAddress)).to.eq('1')
      expect(await vault.allowance(ownerAddress, spender.address)).to.eq(value)
    })

    it('rejects reused signature', async () => {
      const { v, r, s } = getSignatureFromTypedData(
        ownerPrivateKey,
        await buildData(maxDeadline, spender.address)
      )

      await vault.permit(ownerAddress, spender.address, value, maxDeadline, v, r, s)

      await expect(
        vault.permit(initialHolder.address, spender.address, value, maxDeadline, v, r, s)
      ).to.be.revertedWithCustomError(vault, 'PermitInvalidSigner')
    })

    it('rejects other signature', async () => {
      const otherWallet = EthereumWallet.generate()
      const data = await buildData(maxDeadline, spender.address)
      const { v, r, s } = getSignatureFromTypedData(otherWallet.getPrivateKey(), data)

      await expect(
        vault.permit(ownerAddress, spender.address, value, maxDeadline, v, r, s)
      ).to.be.revertedWithCustomError(vault, 'PermitInvalidSigner')
    })

    it('rejects expired permit', async () => {
      const deadline = ((await getLatestBlockTimestamp()) - 500).toString()
      const { v, r, s } = getSignatureFromTypedData(
        ownerPrivateKey,
        await buildData(deadline, spender.address)
      )

      await expect(
        vault.permit(ownerAddress, spender.address, value, deadline, v, r, s)
      ).to.be.revertedWithCustomError(vault, 'DeadlineExpired')
    })

    it('rejects zero address', async () => {
      const deadline = ((await getLatestBlockTimestamp()) - 500).toString()
      const { v, r, s } = getSignatureFromTypedData(
        ownerPrivateKey,
        await buildData(deadline, ZERO_ADDRESS)
      )

      await expect(
        vault.permit(ownerAddress, ZERO_ADDRESS, value, deadline, v, r, s)
      ).to.be.revertedWithCustomError(vault, 'ZeroAddress')
    })
  })
})
