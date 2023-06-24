import { ethers, network, waffle } from 'hardhat'
import { Wallet } from 'ethers'
import { arrayify, parseEther } from 'ethers/lib/utils'
import { OsToken } from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import {
  EIP712Domain,
  MAX_UINT256,
  ONE_DAY,
  OSTOKEN_NAME,
  OSTOKEN_SYMBOL,
  PANIC_CODES,
  PermitSig,
  ZERO_ADDRESS,
} from './shared/constants'
import { collateralizeEthVault } from './shared/rewards'
import EthereumWallet from 'ethereumjs-wallet'
import {
  domainSeparator,
  getSignatureFromTypedData,
  increaseTime,
  latestTimestamp,
} from './shared/utils'

const createFixtureLoader = waffle.createFixtureLoader

describe('OsToken', () => {
  const assets = parseEther('2')
  const initialSupply = 1000
  let initialHolder: Wallet, spender: Wallet, admin: Wallet, owner: Wallet, recipient: Wallet
  let vaultImpl: string
  let osToken: OsToken
  let loadFixture: ReturnType<typeof createFixtureLoader>

  before('create fixture loader', async () => {
    ;[initialHolder, owner, admin, spender, recipient] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([owner])
  })

  beforeEach('deploy fixture', async () => {
    const fixture = await loadFixture(ethVaultFixture)
    const vaultParams = {
      capacity: parseEther('1000'),
      feePercent: 1000,
      metadataIpfsHash: 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u',
    }
    osToken = fixture.osToken
    const vault = await fixture.createEthVault(admin, vaultParams)
    vaultImpl = await vault.implementation()
    await osToken.connect(owner).setVaultImplementation(vaultImpl, true)

    // collateralize vault
    await collateralizeEthVault(vault, fixture.keeper, fixture.validatorsRegistry, admin)
    await vault
      .connect(initialHolder)
      .deposit(initialHolder.address, ZERO_ADDRESS, { value: assets })
    await vault
      .connect(initialHolder)
      .mintOsToken(initialHolder.address, initialSupply, ZERO_ADDRESS)
  })

  describe('capacity', () => {
    it('not owner cannot change', async () => {
      await expect(osToken.connect(initialHolder).setCapacity(0)).to.be.revertedWith(
        'Ownable: caller is not the owner'
      )
    })

    it('owner can change', async () => {
      const receipt = await osToken.connect(owner).setCapacity(0)
      await expect(receipt).to.emit(osToken, 'CapacityUpdated').withArgs(0)
      expect(await osToken.capacity()).to.eq(0)
      await snapshotGasCost(receipt)
    })
  })

  describe('treasury', () => {
    it('not owner cannot change', async () => {
      await expect(osToken.connect(initialHolder).setTreasury(owner.address)).to.be.revertedWith(
        'Ownable: caller is not the owner'
      )
    })

    it('cannot set to zero address', async () => {
      await expect(osToken.connect(owner).setTreasury(ZERO_ADDRESS)).to.be.revertedWith(
        'ZeroAddress'
      )
    })

    it('owner can change', async () => {
      const receipt = await osToken.connect(owner).setTreasury(owner.address)
      await expect(receipt).to.emit(osToken, 'TreasuryUpdated').withArgs(owner.address)
      expect(await osToken.treasury()).to.eq(owner.address)
      await snapshotGasCost(receipt)
    })
  })

  describe('fee percent', () => {
    it('not owner cannot change', async () => {
      await expect(osToken.connect(initialHolder).setFeePercent(100)).to.be.revertedWith(
        'Ownable: caller is not the owner'
      )
    })

    it('cannot set to more than 100%', async () => {
      await expect(osToken.connect(owner).setFeePercent(10001)).to.be.revertedWith(
        'InvalidFeePercent'
      )
    })

    it('owner can change', async () => {
      await increaseTime(ONE_DAY * 1000)
      const receipt = await osToken.connect(owner).setFeePercent(100)
      await expect(receipt).to.emit(osToken, 'FeePercentUpdated').withArgs(100)
      await expect(receipt).to.emit(osToken, 'StateUpdated')
      expect(await osToken.feePercent()).to.eq(100)
      await snapshotGasCost(receipt)
    })
  })

  describe('vault implementation', () => {
    it('not owner cannot change', async () => {
      await expect(
        osToken.connect(initialHolder).setVaultImplementation(vaultImpl, false)
      ).to.be.revertedWith('Ownable: caller is not the owner')
    })

    it('cannot set to zero address', async () => {
      await expect(
        osToken.connect(owner).setVaultImplementation(ZERO_ADDRESS, false)
      ).to.be.revertedWith('ZeroAddress')
    })

    it('owner can change', async () => {
      const receipt = await osToken.connect(owner).setVaultImplementation(vaultImpl, false)
      await expect(receipt)
        .to.emit(osToken, 'VaultImplementationUpdated')
        .withArgs(vaultImpl, false)
      expect(await osToken.vaultImplementations(vaultImpl)).to.eq(false)
      await snapshotGasCost(receipt)
    })
  })

  describe('keeper', () => {
    it('not owner cannot change', async () => {
      await expect(osToken.connect(initialHolder).setKeeper(owner.address)).to.be.revertedWith(
        'Ownable: caller is not the owner'
      )
    })

    it('cannot set to zero address', async () => {
      await expect(osToken.connect(owner).setKeeper(ZERO_ADDRESS)).to.be.revertedWith('ZeroAddress')
    })

    it('owner can change', async () => {
      const receipt = await osToken.connect(owner).setKeeper(owner.address)
      await expect(receipt).to.emit(osToken, 'KeeperUpdated').withArgs(owner.address)
      expect(await osToken.keeper()).to.eq(owner.address)
      await snapshotGasCost(receipt)
    })
  })

  describe('avg reward per second', () => {
    it('not owner cannot change', async () => {
      await expect(osToken.connect(owner).setAvgRewardPerSecond(0)).to.be.revertedWith(
        'AccessDenied'
      )
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
        expect(await osToken.balanceOf(initialHolder.address)).to.eq(initialSupply)
      })
    })
  })

  describe('transfer', () => {
    const balance = initialSupply

    it('reverts when the sender does not have enough balance', async () => {
      const amount = balance + 1
      await expect(
        osToken.connect(initialHolder).transfer(recipient.address, amount)
      ).to.be.revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
    })

    it('reverts with zero address recipient', async () => {
      await expect(
        osToken.connect(initialHolder).transfer(ZERO_ADDRESS, balance)
      ).to.be.revertedWith('ZeroAddress')
    })

    describe('when the sender transfers all balance', () => {
      const amount = initialSupply

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
      const balance = initialSupply

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
        await osToken.connect(initialHolder).approve(spender.address, initialSupply)
      })

      describe('when the token owner has enough balance', () => {
        const amount = initialSupply

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
        const amount = initialSupply

        beforeEach('reducing balance', async () => {
          await osToken.connect(initialHolder).transfer(spender.address, 1)
        })

        it('reverts', async () => {
          await expect(
            osToken.connect(spender).transferFrom(initialHolder.address, spender.address, amount)
          ).to.be.revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
        })
      })
    })

    describe('when the spender does not have enough allowance', () => {
      const allowance = initialSupply - 1

      beforeEach(async () => {
        await osToken.connect(initialHolder).approve(spender.address, allowance)
      })

      describe('when the token owner has enough balance', () => {
        const amount = initialSupply

        it('reverts', async () => {
          await expect(
            osToken.connect(spender).transferFrom(initialHolder.address, spender.address, amount)
          ).to.be.revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
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
          ).to.be.revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
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
      const amount = parseEther('1')
      await expect(osToken.connect(initialHolder).approve(ZERO_ADDRESS, amount)).to.be.revertedWith(
        'ZeroAddress'
      )
    })

    describe('when the sender has enough balance', () => {
      const amount = initialSupply

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
      const amount = initialSupply + 1

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

    describe('increase allowance', () => {
      const amount = initialSupply

      describe('when the spender is not the zero address', () => {
        describe('when the sender has enough balance', () => {
          it('emits an approval event', async () => {
            await expect(osToken.connect(initialHolder).increaseAllowance(spender.address, amount))
              .to.emit(osToken, 'Approval')
              .withArgs(initialHolder.address, spender.address, amount)
          })

          describe('when there was no approved amount before', () => {
            it('approves the requested amount', async () => {
              await osToken.connect(initialHolder).increaseAllowance(spender.address, amount)
              expect(await osToken.allowance(initialHolder.address, spender.address)).to.eq(amount)
            })
          })

          describe('when the spender had an approved amount', () => {
            beforeEach(async () => {
              await osToken.connect(initialHolder).approve(spender.address, 1)
            })

            it('increases the spender allowance adding the requested amount', async () => {
              await osToken.connect(initialHolder).increaseAllowance(spender.address, amount)
              expect(await osToken.allowance(initialHolder.address, spender.address)).to.be.eq(
                amount + 1
              )
            })
          })
        })

        describe('when the sender does not have enough balance', () => {
          const amount = initialSupply + 1

          it('emits an approval event', async () => {
            await expect(osToken.connect(initialHolder).increaseAllowance(spender.address, amount))
              .to.emit(osToken, 'Approval')
              .withArgs(initialHolder.address, spender.address, amount)
          })

          describe('when there was no approved amount before', () => {
            it('approves the requested amount', async () => {
              const receipt = await osToken
                .connect(initialHolder)
                .increaseAllowance(spender.address, amount)
              expect(await osToken.allowance(initialHolder.address, spender.address)).to.eq(amount)
              await snapshotGasCost(receipt)
            })
          })

          describe('when the spender had an approved amount', () => {
            beforeEach(async () => {
              await osToken.connect(initialHolder).approve(spender.address, 1)
            })

            it('increases the spender allowance adding the requested amount', async () => {
              const receipt = await osToken
                .connect(initialHolder)
                .increaseAllowance(spender.address, amount)
              expect(await osToken.allowance(initialHolder.address, spender.address)).to.eq(
                amount + 1
              )
              await snapshotGasCost(receipt)
            })
          })
        })
      })

      describe('when the spender is the zero address', () => {
        it('reverts', async () => {
          await expect(
            osToken.connect(initialHolder).increaseAllowance(ZERO_ADDRESS, amount)
          ).to.be.revertedWith('ZeroAddress')
        })
      })
    })

    describe('decrease allowance', () => {
      describe('when the spender is not the zero address', () => {
        function shouldDecreaseApproval(amount) {
          describe('when there was no approved amount before', () => {
            it('reverts', async () => {
              await expect(
                osToken.connect(initialHolder).decreaseAllowance(spender.address, amount)
              ).to.be.revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
            })
          })

          describe('when the spender had an approved amount', () => {
            const approvedAmount = amount

            beforeEach(async () => {
              await osToken.connect(initialHolder).approve(spender.address, approvedAmount)
            })

            it('emits an approval event', async () => {
              const receipt = await osToken
                .connect(initialHolder)
                .decreaseAllowance(spender.address, approvedAmount)
              await expect(receipt)
                .to.emit(osToken, 'Approval')
                .withArgs(initialHolder.address, spender.address, 0)
              await snapshotGasCost(receipt)
            })

            it('decreases the spender allowance subtracting the requested amount', async () => {
              const receipt = await osToken
                .connect(initialHolder)
                .decreaseAllowance(spender.address, approvedAmount - 1)
              expect(await osToken.allowance(initialHolder.address, spender.address)).to.eq('1')
              await snapshotGasCost(receipt)
            })

            it('sets the allowance to zero when all allowance is removed', async () => {
              await osToken
                .connect(initialHolder)
                .decreaseAllowance(spender.address, approvedAmount)
              expect(await osToken.allowance(initialHolder.address, spender.address)).to.eq('0')
            })

            it('reverts when more than the full allowance is removed', async () => {
              await expect(
                osToken
                  .connect(initialHolder)
                  .decreaseAllowance(spender.address, approvedAmount + 1)
              ).to.be.revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
            })
          })
        }

        describe('when the sender has enough balance', () => {
          shouldDecreaseApproval(initialSupply)
        })

        describe('when the sender does not have enough balance', () => {
          const amount = initialSupply + 1

          shouldDecreaseApproval(amount)
        })
      })

      describe('when the spender is the zero address', () => {
        const amount = initialSupply
        const spender = ZERO_ADDRESS

        it('reverts', async () => {
          await expect(
            osToken.connect(initialHolder).decreaseAllowance(spender, amount)
          ).to.be.revertedWith(PANIC_CODES.ARITHMETIC_UNDER_OR_OVERFLOW)
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

    const buildData = (deadline = maxDeadline, spender) => ({
      primaryType: 'Permit',
      types: { EIP712Domain, Permit: PermitSig },
      domain: {
        name: OSTOKEN_NAME,
        version: '1',
        chainId,
        verifyingContract: osToken.address,
      },
      message: { owner: ownerAddress, spender, value, nonce, deadline },
    })

    it('initial nonce is 0', async () => {
      expect(await osToken.nonces(ownerAddress)).to.eq(0)
    })

    it('domain separator', async () => {
      expect(await osToken.DOMAIN_SEPARATOR()).to.equal(
        await domainSeparator(OSTOKEN_NAME, '1', chainId, osToken.address)
      )
    })

    it('accepts owner signature', async () => {
      const { v, r, s } = getSignatureFromTypedData(
        ownerPrivateKey,
        buildData(maxDeadline, spender.address)
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
        buildData(maxDeadline, spender.address)
      )

      await osToken.permit(ownerAddress, spender.address, value, maxDeadline, v, r, s)

      await expect(
        osToken.permit(initialHolder.address, spender.address, value, maxDeadline, v, r, s)
      ).to.be.revertedWith('PermitInvalidSigner')
    })

    it('rejects other signature', async () => {
      const otherWallet = EthereumWallet.generate()
      const data = buildData(maxDeadline, spender.address)
      const { v, r, s } = getSignatureFromTypedData(otherWallet.getPrivateKey(), data)

      await expect(
        osToken.permit(ownerAddress, spender.address, value, maxDeadline, v, r, s)
      ).to.be.revertedWith('PermitInvalidSigner')
    })

    it('rejects expired permit', async () => {
      const deadline = (await latestTimestamp()).sub(500).toString()
      const { v, r, s } = getSignatureFromTypedData(
        ownerPrivateKey,
        buildData(deadline, spender.address)
      )

      await expect(
        osToken.permit(ownerAddress, spender.address, value, deadline, v, r, s)
      ).to.be.revertedWith('PermitDeadlineExpired')
    })

    it('rejects zero address', async () => {
      const deadline = (await latestTimestamp()).sub(500).toString()
      const { v, r, s } = getSignatureFromTypedData(
        ownerPrivateKey,
        buildData(deadline, ZERO_ADDRESS)
      )

      await expect(
        osToken.permit(ownerAddress, ZERO_ADDRESS, value, deadline, v, r, s)
      ).to.be.revertedWith('ZeroAddress')
    })
  })
})
