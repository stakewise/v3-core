import { ethers, network, waffle } from 'hardhat'
import keccak256 from 'keccak256'
import { Wallet } from 'ethers'
import { toUtf8Bytes } from 'ethers/lib/utils'
import { SignTypedDataVersion, TypedDataUtils } from '@metamask/eth-sig-util'
import EthereumWallet from 'ethereumjs-wallet'
import { Signers } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import { createSigners, ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import snapshotGasCost from './shared/snapshotGasCost'
import { EIP712Domain, REQUIRED_SIGNERS, SIGNERS, OracleSig } from './shared/constants'

const createFixtureLoader = waffle.createFixtureLoader

describe('Signers', () => {
  let owner: Wallet, signer: Wallet, other: Wallet
  let signers: Signers
  let totalSigners: number
  let getSignatures: ThenArg<ReturnType<typeof ethVaultFixture>>['getSignatures']

  let loadFixture: ReturnType<typeof createFixtureLoader>

  before('create fixture loader', async () => {
    ;[owner, signer, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([owner])
  })

  beforeEach('deploy fixture', async () => {
    ;({ signers, getSignatures } = await loadFixture(ethVaultFixture))
    totalSigners = (await signers.totalSigners()).toNumber()
  })

  describe('deploy signers', () => {
    it('fails without initial signers', async () => {
      await expect(createSigners(owner, [], REQUIRED_SIGNERS)).revertedWith(
        'InvalidRequiredSigners()'
      )
    })

    it('fails with zero required signers', async () => {
      await expect(
        createSigners(
          owner,
          SIGNERS.map((s) => new EthereumWallet(s).getAddressString()),
          0
        )
      ).revertedWith('InvalidRequiredSigners()')
    })
  })

  describe('add signer', () => {
    it('fails if not owner', async () => {
      await expect(signers.connect(other).addSigner(signer.address)).revertedWith(
        'Ownable: caller is not the owner'
      )
    })

    it('fails if already added', async () => {
      await signers.connect(owner).addSigner(signer.address)
      await expect(signers.connect(owner).addSigner(signer.address)).revertedWith('AlreadyAdded()')
    })

    it('succeeds', async () => {
      const receipt = await signers.connect(owner).addSigner(signer.address)
      await expect(receipt).to.emit(signers, 'SignerAdded').withArgs(signer.address)
      expect(await signers.isSigner(signer.address)).to.be.eq(true)
      expect(await signers.totalSigners()).to.be.eq(totalSigners + 1)
      await snapshotGasCost(receipt)
    })
  })

  describe('remove signer', () => {
    let totalSigners: number

    beforeEach(async () => {
      await signers.connect(owner).addSigner(signer.address)
      totalSigners = (await signers.totalSigners()).toNumber()
    })

    it('fails if not owner', async () => {
      await expect(signers.connect(other).removeSigner(signer.address)).revertedWith(
        'Ownable: caller is not the owner'
      )
    })

    it('fails if already removed', async () => {
      await signers.connect(owner).removeSigner(signer.address)
      await expect(signers.connect(owner).removeSigner(signer.address)).revertedWith(
        'AlreadyRemoved()'
      )
    })

    it('fails to remove all signers', async () => {
      for (let i = 0; i < SIGNERS.length; i++) {
        await signers.connect(owner).removeSigner(new EthereumWallet(SIGNERS[i]).getAddressString())
      }
      await expect(signers.connect(owner).removeSigner(signer.address)).revertedWith(
        'InvalidRequiredSigners()'
      )
    })

    it('decreases required signers', async () => {
      await signers.connect(owner).setRequiredSigners(totalSigners)
      expect(await signers.requiredSigners()).to.be.eq(totalSigners)

      const receipt = await signers.connect(owner).removeSigner(signer.address)
      await expect(receipt).to.emit(signers, 'SignerRemoved').withArgs(signer.address)
      await expect(receipt)
        .to.emit(signers, 'RequiredSignersUpdated')
        .withArgs(totalSigners - 1)

      expect(await signers.isSigner(signer.address)).to.be.eq(false)
      expect(await signers.totalSigners()).to.be.eq(totalSigners - 1)
      expect(await signers.requiredSigners()).to.be.eq(totalSigners - 1)
      await snapshotGasCost(receipt)
    })

    it('succeeds', async () => {
      const receipt = await signers.connect(owner).removeSigner(signer.address)
      await expect(receipt).to.emit(signers, 'SignerRemoved').withArgs(signer.address)
      expect(await signers.isSigner(signer.address)).to.be.eq(false)
      expect(await signers.totalSigners()).to.be.eq(totalSigners - 1)
      await snapshotGasCost(receipt)
    })
  })

  describe('set required signers', () => {
    it('fails if not owner', async () => {
      await expect(signers.connect(other).setRequiredSigners(1)).revertedWith(
        'Ownable: caller is not the owner'
      )
    })

    it('fails with number larger than total signers', async () => {
      await expect(signers.connect(owner).setRequiredSigners(totalSigners + 1)).revertedWith(
        'InvalidRequiredSigners()'
      )
    })

    it('succeeds', async () => {
      const receipt = await signers.connect(owner).setRequiredSigners(1)
      await expect(receipt).to.emit(signers, 'RequiredSignersUpdated').withArgs(1)
      expect(await signers.requiredSigners()).to.be.eq(1)
      await snapshotGasCost(receipt)
    })
  })

  describe('verify signers', () => {
    const rewardsRoot = '0x059a8487a1ce461e9670c4646ef85164ae8791613866d28c972fb351dc45c606'
    const rewardsIpfsHash = keccak256(
      Buffer.from(toUtf8Bytes('/ipfs/QmfPnyNojfyqoi9yqS3jMp16GGiTQee4bdCXJC64KqvTgc'))
    )
    const nonce = 1
    let signData
    let verifyData

    beforeEach(async () => {
      signData = {
        primaryType: 'Oracle',
        types: { EIP712Domain, Oracle: OracleSig },
        domain: {
          name: 'Signers',
          version: '1',
          chainId: network.config.chainId,
          verifyingContract: signers.address,
        },
        message: { rewardsRoot, rewardsIpfsHash, nonce },
      }
      verifyData = TypedDataUtils.hashStruct(
        'Oracle',
        signData.message,
        signData.types,
        SignTypedDataVersion.V4
      )
    })

    it('fails with invalid signatures length', async () => {
      const signatures = getSignatures(signData, 5)
      await expect(signers.verifySignatures(verifyData, signatures)).revertedWith(
        'NotEnoughSignatures()'
      )
    })

    it('fails with repeated signature', async () => {
      const signatures = Buffer.concat([getSignatures(signData, 5), getSignatures(signData, 1)])
      await expect(signers.verifySignatures(verifyData, signatures)).revertedWith('InvalidSigner()')
    })

    it('fails with invalid signer', async () => {
      await signers.connect(owner).removeSigner(new EthereumWallet(SIGNERS[0]).getAddressString())
      await expect(
        signers.verifySignatures(verifyData, getSignatures(signData, REQUIRED_SIGNERS))
      ).revertedWith('InvalidSigner()')
    })

    it('succeeds with required signatures', async () => {
      const SignersMock = await ethers.getContractFactory('SignersMock')
      const signersMock = await SignersMock.deploy(signers.address)
      const receipt = await signersMock.getGasCostOfVerifySignatures(
        verifyData,
        getSignatures(signData, REQUIRED_SIGNERS)
      )
      await snapshotGasCost(receipt)
    })

    it('succeeds with all signatures', async () => {
      const SignersMock = await ethers.getContractFactory('SignersMock')
      const signersMock = await SignersMock.deploy(signers.address)
      const receipt = await signersMock.getGasCostOfVerifySignatures(
        verifyData,
        getSignatures(signData, SIGNERS.length)
      )
      await snapshotGasCost(receipt)
    })
  })
})
