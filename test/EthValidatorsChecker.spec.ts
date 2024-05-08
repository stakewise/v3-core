import { SignTypedDataVersion, signTypedData } from '@metamask/eth-sig-util'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { Contract, Signer, Wallet } from 'ethers'
import { ethers } from 'hardhat'
import keccak256 from 'keccak256'
import {
  DepositDataRegistry,
  EthValidatorsChecker,
  EthVault,
  Keeper,
  VaultsRegistry,
} from '../typechain-types'
import { MAX_UINT256, ZERO_ADDRESS } from './shared/constants'
import { getEthVaultV1Factory } from './shared/contracts'
import { expect } from './shared/expect'
import { deployEthVaultV1, encodeEthVaultInitParams, ethVaultFixture } from './shared/fixtures'
import {
  EthValidatorsData,
  createEthValidatorsData,
  createValidatorPublicKeys,
  getEthValidatorsCheckerSigningData,
  getValidatorsMultiProof,
} from './shared/validators'

describe('EthValidatorsChecker', () => {
  const validatorDeposit = ethers.parseEther('32')
  const capacity = MAX_UINT256
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'

  let admin: Signer, adminV1: Signer, other: Wallet
  let vault: EthVault,
    keeper: Keeper,
    validatorsRegistry: Contract,
    vaultsRegistry: VaultsRegistry,
    depositDataRegistry: DepositDataRegistry,
    ethValidatorsChecker: EthValidatorsChecker,
    vaultV1: Contract,
    vaultNotDeposited: EthVault
  let validatorsData: EthValidatorsData
  let publicKeys: Uint8Array[]
  let validatorsRegistryRoot: string

  beforeEach('deploy fixture', async () => {
    ;[admin, adminV1, other] = await (ethers as any).getSigners()

    const fixture = await loadFixture(ethVaultFixture)
    validatorsRegistry = fixture.validatorsRegistry
    keeper = fixture.keeper
    depositDataRegistry = fixture.depositDataRegistry
    ethValidatorsChecker = fixture.ethValidatorsChecker
    vaultsRegistry = fixture.vaultsRegistry

    vault = await fixture.createEthVault(admin, {
      capacity,
      feePercent,
      metadataIpfsHash,
    })
    vaultV1 = await deployEthVaultV1(
      await getEthVaultV1Factory(),
      adminV1,
      keeper,
      vaultsRegistry,
      validatorsRegistry,
      fixture.osTokenVaultController,
      fixture.osTokenConfig,
      fixture.sharedMevEscrow,
      encodeEthVaultInitParams({
        capacity,
        feePercent,
        metadataIpfsHash,
      })
    )
    // get real admin in the case of mainnet fork
    admin = await ethers.getImpersonatedSigner(await vault.admin())

    validatorsData = await createEthValidatorsData(vault)
    publicKeys = await createValidatorPublicKeys()
    validatorsRegistryRoot = await validatorsRegistry.get_deposit_root()
    await vault.connect(other).deposit(other.address, ZERO_ADDRESS, { value: validatorDeposit })
    await vaultV1.connect(other).deposit(other.address, ZERO_ADDRESS, { value: validatorDeposit })

    vaultNotDeposited = await fixture.createEthVault(
      admin,
      {
        capacity,
        feePercent,
        metadataIpfsHash,
      },
      true, // own mev escrow
      true // skip fork
    )
    await vaultNotDeposited
      .connect(other)
      .deposit(other.address, ZERO_ADDRESS, { value: ethers.parseEther('31') })

    await depositDataRegistry
      .connect(admin)
      .setDepositDataRoot(await vault.getAddress(), validatorsData.root)

    await vaultV1.connect(adminV1).setValidatorsRoot(validatorsData.root)
    await depositDataRegistry
      .connect(admin)
      .setDepositDataRoot(await vaultNotDeposited.getAddress(), validatorsData.root)
  })

  describe('check validators manager signature', () => {
    async function validatorsManagerSetup() {
      // I need explicit privateKey to create EIP-712 signature
      const validatorsManager = new Wallet(
        '0x798ce32ec683f3287dab0594b9ead26403a6da9c1d216d00e5aa088c9cf36864'
      )
      const fakeValidatorsManager = new Wallet(
        '0xb4942e4f87ddfd23ddf833a47ebcf6bb37e0da344a2d6e229fd593c0b22bdb68'
      )
      await vault.connect(admin).setValidatorsManager(validatorsManager.address)
      return {
        validatorsManager,
        fakeValidatorsManager,
      }
    }

    it('fails for invalid validators registry root', async () => {
      const fakeRoot = Buffer.alloc(32).fill(1)
      await expect(
        ethValidatorsChecker
          .connect(admin)
          .checkValidatorsManagerSignature(await vault.getAddress(), fakeRoot, '0x', '0x')
      ).to.be.revertedWithCustomError(ethValidatorsChecker, 'InvalidValidatorsRegistryRoot')
    })

    it('fails for non-vault', async () => {
      await expect(
        ethValidatorsChecker
          .connect(admin)
          .checkValidatorsManagerSignature(other.address, validatorsRegistryRoot, '0x', '0x')
      ).to.be.revertedWithCustomError(ethValidatorsChecker, 'InvalidVault')
    })

    it('fails for vault v1', async () => {
      await expect(
        ethValidatorsChecker
          .connect(admin)
          .checkValidatorsManagerSignature(
            await vaultV1.getAddress(),
            validatorsRegistryRoot,
            '0x',
            '0x'
          )
      ).to.be.revertedWithCustomError(ethValidatorsChecker, 'InvalidVault')
    })

    it('fails for vault not collateralized not deposited', async () => {
      await expect(
        ethValidatorsChecker
          .connect(admin)
          .checkValidatorsManagerSignature(
            await vaultNotDeposited.getAddress(),
            validatorsRegistryRoot,
            '0x',
            '0x'
          )
      ).to.be.revertedWithCustomError(ethValidatorsChecker, 'InsufficientAssets')
    })

    it('fails for signer who is not validators manager', async () => {
      const { fakeValidatorsManager } = await validatorsManagerSetup()
      const vaultAddress = await vault.getAddress()
      const typedData = await getEthValidatorsCheckerSigningData(
        keccak256(Buffer.concat(publicKeys)),
        ethValidatorsChecker,
        vault,
        validatorsRegistryRoot
      )
      const signature = signTypedData({
        privateKey: Buffer.from(ethers.getBytes(fakeValidatorsManager.privateKey)),
        data: typedData,
        version: SignTypedDataVersion.V4,
      })
      await expect(
        ethValidatorsChecker
          .connect(admin)
          .checkValidatorsManagerSignature(
            vaultAddress,
            validatorsRegistryRoot,
            Buffer.concat(publicKeys),
            ethers.getBytes(signature)
          )
      ).to.be.revertedWithCustomError(ethValidatorsChecker, 'AccessDenied')
    })

    it('succeeds', async () => {
      const { validatorsManager } = await validatorsManagerSetup()
      const vaultAddress = await vault.getAddress()
      const typedData = await getEthValidatorsCheckerSigningData(
        Buffer.concat(publicKeys),
        ethValidatorsChecker,
        vault,
        validatorsRegistryRoot
      )
      const signature = signTypedData({
        privateKey: Buffer.from(ethers.getBytes(validatorsManager.privateKey)),
        data: typedData,
        version: SignTypedDataVersion.V4,
      })
      const blockNumber = await ethers.provider.getBlockNumber()

      expect(
        await ethValidatorsChecker
          .connect(admin)
          .checkValidatorsManagerSignature(
            vaultAddress,
            validatorsRegistryRoot,
            Buffer.concat(publicKeys),
            ethers.getBytes(signature)
          )
      ).to.eq(blockNumber)
    })
  })

  describe('check deposit data root', () => {
    function getMultiProofArgs(options?: any) {
      options = options || {}
      let validators = validatorsData.validators

      if (options.numValidators !== undefined) {
        validators = validators.slice(0, options.numValidators)
      }

      const multiProof = getValidatorsMultiProof(validatorsData.tree, validators, [
        ...Array(validators.length).keys(),
      ])
      const sortedVals = multiProof.leaves.map((v) => v[0])
      const proofIndexes = validators.map((v) => sortedVals.indexOf(v))

      return {
        proof: multiProof.proof,
        proofFlags: multiProof.proofFlags,
        proofIndexes,
      }
    }

    it('fails for invalid validators registry root', async () => {
      const fakeRoot = Buffer.alloc(32).fill(1)
      const { proof, proofFlags, proofIndexes } = getMultiProofArgs()

      await expect(
        ethValidatorsChecker
          .connect(admin)
          .checkDepositDataRoot(
            await vault.getAddress(),
            fakeRoot,
            Buffer.concat(validatorsData.validators),
            proof,
            proofFlags,
            proofIndexes
          )
      ).to.be.revertedWithCustomError(ethValidatorsChecker, 'InvalidValidatorsRegistryRoot')
    })

    it('fails for non-vault', async () => {
      const { proof, proofFlags, proofIndexes } = getMultiProofArgs()

      await expect(
        ethValidatorsChecker
          .connect(admin)
          .checkDepositDataRoot(
            other.address,
            validatorsRegistryRoot,
            Buffer.concat(validatorsData.validators),
            proof,
            proofFlags,
            proofIndexes
          )
      ).to.be.revertedWithCustomError(ethValidatorsChecker, 'InvalidVault')
    })

    it('fails for vault not collateralized not deposited', async () => {
      const { proof, proofFlags, proofIndexes } = getMultiProofArgs()

      await expect(
        ethValidatorsChecker
          .connect(admin)
          .checkDepositDataRoot(
            await vaultNotDeposited.getAddress(),
            validatorsRegistryRoot,
            Buffer.concat(validatorsData.validators),
            proof,
            proofFlags,
            proofIndexes
          )
      ).to.be.revertedWithCustomError(ethValidatorsChecker, 'InsufficientAssets')
    })

    it('fails for validators manager not equal to deposit data registry', async () => {
      await vault.connect(admin).setValidatorsManager(other.address)
      const { proof, proofFlags, proofIndexes } = getMultiProofArgs()

      await expect(
        ethValidatorsChecker
          .connect(admin)
          .checkDepositDataRoot(
            await vault.getAddress(),
            validatorsRegistryRoot,
            Buffer.concat(validatorsData.validators),
            proof,
            proofFlags,
            proofIndexes
          )
      ).to.be.revertedWithCustomError(ethValidatorsChecker, 'AccessDenied')
    })

    it('fails for invalid proof', async () => {
      const { proof, proofFlags, proofIndexes } = getMultiProofArgs({ numValidators: 1 })
      proof[0] = '0x' + '1'.repeat(64)

      await expect(
        ethValidatorsChecker
          .connect(admin)
          .checkDepositDataRoot(
            await vault.getAddress(),
            validatorsRegistryRoot,
            Buffer.concat(validatorsData.validators),
            proof,
            proofFlags,
            proofIndexes
          )
      ).to.be.revertedWithCustomError(ethValidatorsChecker, 'InvalidProof')
    })

    it('succeeds for vault v1', async () => {
      const { proof, proofFlags, proofIndexes } = getMultiProofArgs()
      const blockNumber = await ethers.provider.getBlockNumber()

      expect(
        await ethValidatorsChecker
          .connect(admin)
          .checkDepositDataRoot(
            await vaultV1.getAddress(),
            validatorsRegistryRoot,
            Buffer.concat(validatorsData.validators),
            proof,
            proofFlags,
            proofIndexes
          )
      ).to.eq(blockNumber)
    })

    it('succeeds for vault v2', async () => {
      const { proof, proofFlags, proofIndexes } = getMultiProofArgs()
      const blockNumber = await ethers.provider.getBlockNumber()

      expect(
        await ethValidatorsChecker
          .connect(admin)
          .checkDepositDataRoot(
            await vault.getAddress(),
            validatorsRegistryRoot,
            Buffer.concat(validatorsData.validators),
            proof,
            proofFlags,
            proofIndexes
          )
      ).to.eq(blockNumber)
    })
  })
})
