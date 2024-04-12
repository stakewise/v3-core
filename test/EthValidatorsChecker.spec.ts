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
  ValidatorsMultiProof,
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

  let admin: Signer,
    other: Wallet,
    depositDataManager: Wallet,
    validatorsManager: Wallet,
    fakeValidatorsManager: Wallet
  let vault: EthVault,
    keeper: Keeper,
    validatorsRegistry: Contract,
    vaultsRegistry: VaultsRegistry,
    depositDataRegistry: DepositDataRegistry,
    ethValidatorsChecker: EthValidatorsChecker,
    vaultV1: Contract,
    vaultNotDeposited: EthVault,
    vaultWithDepositDataManager: EthVault
  let validatorsData: EthValidatorsData
  let publicKeys: Uint8Array[]
  let validatorsRegistryRoot: string

  let multiProof: ValidatorsMultiProof
  let proofIndexes: number[]

  before('deploy fixture', async () => {
    ;[admin, other, depositDataManager] = await (ethers as any).getSigners()

    // privateKey attribute non-empty
    validatorsManager = new Wallet(
      '0x798ce32ec683f3287dab0594b9ead26403a6da9c1d216d00e5aa088c9cf36864'
    )
    fakeValidatorsManager = new Wallet(
      '0xb4942e4f87ddfd23ddf833a47ebcf6bb37e0da344a2d6e229fd593c0b22bdb68'
    )

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
    vaultWithDepositDataManager = await fixture.createEthVault(admin, {
      capacity,
      feePercent,
      metadataIpfsHash,
    })
    await vault.connect(admin).setValidatorsManager(validatorsManager.address)
    vaultV1 = await deployEthVaultV1(
      await getEthVaultV1Factory(),
      admin,
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
    admin = await ethers.getImpersonatedSigner(await vault.admin())
    validatorsData = await createEthValidatorsData(vault)
    publicKeys = await createValidatorPublicKeys()
    validatorsRegistryRoot = await validatorsRegistry.get_deposit_root()
    await vault.connect(other).deposit(other.address, ZERO_ADDRESS, { value: validatorDeposit })
    await vaultV1.connect(other).deposit(other.address, ZERO_ADDRESS, { value: validatorDeposit })

    vaultNotDeposited = await fixture.createEthVault(admin, {
      capacity,
      feePercent,
      metadataIpfsHash,
    })
    await vaultNotDeposited
      .connect(other)
      .deposit(other.address, ZERO_ADDRESS, { value: ethers.parseEther('31') })

    await vaultWithDepositDataManager.connect(admin).setValidatorsManager(validatorsManager.address)
    depositDataRegistry
      .connect(admin)
      .setDepositDataManager(
        await vaultWithDepositDataManager.getAddress(),
        depositDataManager.address
      )

    const validators = validatorsData.validators

    multiProof = getValidatorsMultiProof(validatorsData.tree, validators, [
      ...Array(validators.length).keys(),
    ])
    const sortedVals = multiProof.leaves.map((v) => v[0])
    proofIndexes = validators.map((v) => sortedVals.indexOf(v))

    await depositDataRegistry
      .connect(admin)
      .setDepositDataRoot(await vault.getAddress(), validatorsData.root)
    await vaultV1.connect(admin).setValidatorsRoot(validatorsData.root)
    await depositDataRegistry
      .connect(admin)
      .setDepositDataRoot(await vaultNotDeposited.getAddress(), validatorsData.root)
    await depositDataRegistry
      .connect(depositDataManager)
      .setDepositDataRoot(await vaultWithDepositDataManager.getAddress(), validatorsData.root)
  })

  describe('check validators manager signature', () => {
    it('fails for invalid validators registry root', async () => {
      const fakeRoot = Buffer.alloc(32).fill(1)
      await expect(
        ethValidatorsChecker
          .connect(admin)
          .checkValidatorsManagerSignature(
            await vault.getAddress(),
            fakeRoot,
            Buffer.from('', 'utf-8'),
            Buffer.from('', 'utf-8')
          )
      ).to.be.revertedWithCustomError(ethValidatorsChecker, 'InvalidValidatorsRegistryRoot')
    })

    it('fails for non-vault', async () => {
      await expect(
        ethValidatorsChecker
          .connect(admin)
          .checkValidatorsManagerSignature(
            other.address,
            validatorsRegistryRoot,
            Buffer.from('', 'utf-8'),
            Buffer.from('', 'utf-8')
          )
      ).to.be.revertedWithCustomError(ethValidatorsChecker, 'InvalidVault')
    })

    it('fails for vault v1', async () => {
      await expect(
        ethValidatorsChecker
          .connect(admin)
          .checkValidatorsManagerSignature(
            await vaultV1.getAddress(),
            validatorsRegistryRoot,
            Buffer.from('', 'utf-8'),
            Buffer.from('', 'utf-8')
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
            Buffer.from('', 'utf-8'),
            Buffer.from('', 'utf-8')
          )
      ).to.be.revertedWithCustomError(ethValidatorsChecker, 'AccessDenied')
    })

    it('fails for signer who is not validators manager', async () => {
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

      await expect(
        ethValidatorsChecker
          .connect(admin)
          .checkValidatorsManagerSignature(
            vaultAddress,
            validatorsRegistryRoot,
            Buffer.concat(publicKeys),
            ethers.getBytes(signature)
          )
      ).to.eventually.be.greaterThan(0)
    })
  })

  describe('check deposit data root', () => {
    it('fails for invalid validators registry root', async () => {
      const fakeRoot = Buffer.alloc(32).fill(1)
      await expect(
        ethValidatorsChecker
          .connect(admin)
          .checkDepositDataRoot(
            await vault.getAddress(),
            fakeRoot,
            Buffer.concat(validatorsData.validators),
            multiProof.proof,
            multiProof.proofFlags,
            proofIndexes
          )
      ).to.be.revertedWithCustomError(ethValidatorsChecker, 'InvalidValidatorsRegistryRoot')
    })

    it('fails for non-vault', async () => {
      await expect(
        ethValidatorsChecker
          .connect(admin)
          .checkDepositDataRoot(
            other.address,
            validatorsRegistryRoot,
            Buffer.concat(validatorsData.validators),
            multiProof.proof,
            multiProof.proofFlags,
            proofIndexes
          )
      ).to.be.revertedWithCustomError(ethValidatorsChecker, 'InvalidVault')
    })

    it('fails for vault not collateralized not deposited', async () => {
      await expect(
        ethValidatorsChecker
          .connect(admin)
          .checkDepositDataRoot(
            await vaultNotDeposited.getAddress(),
            validatorsRegistryRoot,
            Buffer.concat(validatorsData.validators),
            multiProof.proof,
            multiProof.proofFlags,
            proofIndexes
          )
      ).to.be.revertedWithCustomError(ethValidatorsChecker, 'AccessDenied')
    })

    it('fails for validators manager not equal to deposit data manager', async () => {
      await expect(
        ethValidatorsChecker
          .connect(admin)
          .checkDepositDataRoot(
            await vaultWithDepositDataManager.getAddress(),
            validatorsRegistryRoot,
            Buffer.concat(validatorsData.validators),
            multiProof.proof,
            multiProof.proofFlags,
            proofIndexes
          )
      ).to.be.revertedWithCustomError(ethValidatorsChecker, 'AccessDenied')
    })

    it('succeeds for vault v1', async () => {
      await expect(
        ethValidatorsChecker
          .connect(admin)
          .checkDepositDataRoot(
            await vaultV1.getAddress(),
            validatorsRegistryRoot,
            Buffer.concat(validatorsData.validators),
            multiProof.proof,
            multiProof.proofFlags,
            proofIndexes
          )
      ).to.eventually.be.greaterThan(0)
    })

    it('succeeds for vault v2', async () => {
      await expect(
        ethValidatorsChecker
          .connect(admin)
          .checkDepositDataRoot(
            await vault.getAddress(),
            validatorsRegistryRoot,
            Buffer.concat(validatorsData.validators),
            multiProof.proof,
            multiProof.proofFlags,
            proofIndexes
          )
      ).to.eventually.be.greaterThan(0)
    })
  })
})
