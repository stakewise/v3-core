import { SignTypedDataVersion, signTypedData } from '@metamask/eth-sig-util'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import { Contract, Signer, Wallet } from 'ethers'
import { ethers } from 'hardhat'
import {
  DepositDataRegistry,
  EthValidatorsChecker,
  GnoValidatorsChecker,
  EthVault,
  Keeper,
  VaultsRegistry,
} from '../typechain-types'
import { MAX_UINT256, ZERO_ADDRESS } from './shared/constants'
import { getEthVaultV1Factory } from './shared/contracts'
import { expect } from './shared/expect'
import {
  createEthValidatorsChecker,
  deployEthVaultV1,
  encodeEthVaultInitParams,
  ethVaultFixture,
} from './shared/fixtures'
import {
  EthValidatorsData,
  createEthValidatorsData,
  createValidatorPublicKeys,
  getValidatorsManagerSigningData,
  getValidatorsMultiProof,
} from './shared/validators'
import { createGnoValidatorsChecker } from './shared/gnoFixtures'

const networks = ['ETHEREUM', 'GNOSIS']

networks.forEach((network) => {
  describe(`ValidatorsChecker [${network}]`, () => {
    let validatorDeposit = ethers.parseEther('32')
    if (network == 'GNOSIS') {
      validatorDeposit = ethers.parseEther('1')
    }

    const capacity = MAX_UINT256
    const feePercent = 1000
    const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'

    let admin: Signer, adminV1: Signer, other: Wallet
    let vault: EthVault,
      keeper: Keeper,
      validatorsRegistry: Contract,
      vaultsRegistry: VaultsRegistry,
      depositDataRegistry: DepositDataRegistry,
      validatorsChecker: EthValidatorsChecker | GnoValidatorsChecker,
      vaultV1: Contract,
      vaultNotDeposited: EthVault
    let validatorsData: EthValidatorsData
    let validators: Buffer[]
    let publicKeys: Uint8Array[]
    let validatorsRegistryRoot: string

    beforeEach('deploy fixture', async () => {
      ;[admin, adminV1, other] = await (ethers as any).getSigners()

      const fixture = await loadFixture(ethVaultFixture)
      validatorsRegistry = fixture.validatorsRegistry
      keeper = fixture.keeper
      depositDataRegistry = fixture.depositDataRegistry
      vaultsRegistry = fixture.vaultsRegistry

      if (network == 'ETHEREUM') {
        validatorsChecker = await createEthValidatorsChecker(
          validatorsRegistry,
          keeper,
          vaultsRegistry,
          depositDataRegistry
        )
      } else if (network == 'GNOSIS') {
        validatorsChecker = await createGnoValidatorsChecker(
          validatorsRegistry,
          keeper,
          vaultsRegistry,
          depositDataRegistry
        )
      } else {
        throw Error('unknown network')
      }

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
      const numValidators = 5
      validators = validatorsData.validators.slice(0, numValidators)

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
      // Remember about security deposit 1 gwei, so vault balance is not zero at this point.
      let validatorDepositIncomplete = ethers.parseEther('31')
      if (network == 'GNOSIS') {
        validatorDepositIncomplete = ethers.parseEther('0.9')
      }
      await vaultNotDeposited
        .connect(other)
        .deposit(other.address, ZERO_ADDRESS, { value: validatorDepositIncomplete })

      await depositDataRegistry
        .connect(admin)
        .setDepositDataRoot(await vault.getAddress(), validatorsData.root)

      await vaultV1.connect(adminV1).setValidatorsRoot(validatorsData.root)
      await depositDataRegistry
        .connect(admin)
        .setDepositDataRoot(await vaultNotDeposited.getAddress(), validatorsData.root)
    })

    describe('check validators manager signature', () => {
      // I need explicit privateKey to create EIP-712 signature
      const validatorsManager = new Wallet(
        '0x798ce32ec683f3287dab0594b9ead26403a6da9c1d216d00e5aa088c9cf36864'
      )
      const fakeValidatorsManager = new Wallet(
        '0xb4942e4f87ddfd23ddf833a47ebcf6bb37e0da344a2d6e229fd593c0b22bdb68'
      )

      beforeEach('set validators manager', async () => {
        await vault.connect(admin).setValidatorsManager(validatorsManager.address)
      })

      it('fails for invalid validators registry root', async () => {
        const fakeRoot = Buffer.alloc(32).fill(1)
        await expect(
          validatorsChecker
            .connect(admin)
            .checkValidatorsManagerSignature(await vault.getAddress(), fakeRoot, '0x', '0x')
        ).to.be.revertedWithCustomError(validatorsChecker, 'InvalidValidatorsRegistryRoot')
      })

      it('fails for non-vault', async () => {
        await expect(
          validatorsChecker
            .connect(admin)
            .checkValidatorsManagerSignature(other.address, validatorsRegistryRoot, '0x', '0x')
        ).to.be.revertedWithCustomError(validatorsChecker, 'InvalidVault')
      })

      it('fails for vault v1', async () => {
        await expect(
          validatorsChecker
            .connect(admin)
            .checkValidatorsManagerSignature(
              await vaultV1.getAddress(),
              validatorsRegistryRoot,
              '0x',
              '0x'
            )
        ).to.be.revertedWithCustomError(validatorsChecker, 'InvalidVault')
      })

      it('fails for vault not collateralized not deposited', async () => {
        await expect(
          validatorsChecker
            .connect(admin)
            .checkValidatorsManagerSignature(
              await vaultNotDeposited.getAddress(),
              validatorsRegistryRoot,
              '0x',
              '0x'
            )
        ).to.be.revertedWithCustomError(validatorsChecker, 'InsufficientAssets')
      })

      it('fails for signer who is not validators manager', async () => {
        const vaultAddress = await vault.getAddress()
        const typedData = await getValidatorsManagerSigningData(
          Buffer.concat(validators),
          vault,
          validatorsRegistryRoot
        )
        const signature = signTypedData({
          privateKey: Buffer.from(ethers.getBytes(fakeValidatorsManager.privateKey)),
          data: typedData,
          version: SignTypedDataVersion.V4,
        })
        await expect(
          validatorsChecker
            .connect(admin)
            .checkValidatorsManagerSignature(
              vaultAddress,
              validatorsRegistryRoot,
              Buffer.concat(publicKeys),
              ethers.getBytes(signature)
            )
        ).to.be.revertedWithCustomError(validatorsChecker, 'AccessDenied')
      })

      it('succeeds', async () => {
        const vaultAddress = await vault.getAddress()
        const typedData = await getValidatorsManagerSigningData(
          Buffer.concat(validators),
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
          await validatorsChecker
            .connect(admin)
            .checkValidatorsManagerSignature(
              vaultAddress,
              validatorsRegistryRoot,
              Buffer.concat(validators),
              ethers.getBytes(signature)
            )
        ).to.eq(blockNumber)
      })
    })

    describe('check deposit data root', () => {
      let proof: string[], proofFlags: boolean[], proofIndexes: number[]

      beforeEach('set multiproof', () => {
        // Proof is empty list when passing all validators
        // I need non-empty proof for some test cases
        // Slice validators because of that

        const multiProof = getValidatorsMultiProof(validatorsData.tree, validators, [
          ...Array(validators.length).keys(),
        ])
        const sortedVals = multiProof.leaves.map((v) => v[0])

        ;(proof = multiProof.proof),
          (proofFlags = multiProof.proofFlags),
          (proofIndexes = validators.map((v) => sortedVals.indexOf(v)))
      })

      it('fails for invalid validators registry root', async () => {
        const fakeRoot = Buffer.alloc(32).fill(1)

        await expect(
          validatorsChecker
            .connect(admin)
            .checkDepositDataRoot(
              await vault.getAddress(),
              fakeRoot,
              Buffer.concat(validators),
              proof,
              proofFlags,
              proofIndexes
            )
        ).to.be.revertedWithCustomError(validatorsChecker, 'InvalidValidatorsRegistryRoot')
      })

      it('fails for non-vault', async () => {
        await expect(
          validatorsChecker
            .connect(admin)
            .checkDepositDataRoot(
              other.address,
              validatorsRegistryRoot,
              Buffer.concat(validators),
              proof,
              proofFlags,
              proofIndexes
            )
        ).to.be.revertedWithCustomError(validatorsChecker, 'InvalidVault')
      })

      it('fails for vault not collateralized not deposited', async () => {
        await expect(
          validatorsChecker
            .connect(admin)
            .checkDepositDataRoot(
              await vaultNotDeposited.getAddress(),
              validatorsRegistryRoot,
              Buffer.concat(validators),
              proof,
              proofFlags,
              proofIndexes
            )
        ).to.be.revertedWithCustomError(validatorsChecker, 'InsufficientAssets')
      })

      it('fails for validators manager not equal to deposit data registry', async () => {
        await vault.connect(admin).setValidatorsManager(other.address)

        await expect(
          validatorsChecker
            .connect(admin)
            .checkDepositDataRoot(
              await vault.getAddress(),
              validatorsRegistryRoot,
              Buffer.concat(validators),
              proof,
              proofFlags,
              proofIndexes
            )
        ).to.be.revertedWithCustomError(validatorsChecker, 'AccessDenied')
      })

      it('fails for invalid proof', async () => {
        proof[0] = '0x' + '1'.repeat(64)

        await expect(
          validatorsChecker
            .connect(admin)
            .checkDepositDataRoot(
              await vault.getAddress(),
              validatorsRegistryRoot,
              Buffer.concat(validators),
              proof,
              proofFlags,
              proofIndexes
            )
        ).to.be.revertedWithCustomError(validatorsChecker, 'InvalidProof')
      })

      it('succeeds for vault v1', async () => {
        const blockNumber = await ethers.provider.getBlockNumber()

        expect(
          await validatorsChecker
            .connect(admin)
            .checkDepositDataRoot(
              await vaultV1.getAddress(),
              validatorsRegistryRoot,
              Buffer.concat(validators),
              proof,
              proofFlags,
              proofIndexes
            )
        ).to.eq(blockNumber)
      })

      it('succeeds for vault v2', async () => {
        const blockNumber = await ethers.provider.getBlockNumber()

        expect(
          await validatorsChecker
            .connect(admin)
            .checkDepositDataRoot(
              await vault.getAddress(),
              validatorsRegistryRoot,
              Buffer.concat(validators),
              proof,
              proofFlags,
              proofIndexes
            )
        ).to.eq(blockNumber)
      })
    })
  })
})
