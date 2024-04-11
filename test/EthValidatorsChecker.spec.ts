import { ethers } from 'hardhat'
import { Contract, Signer, Wallet } from 'ethers'
import { UintNumberType } from '@chainsafe/ssz'
import { loadFixture } from '@nomicfoundation/hardhat-toolbox/network-helpers'
import {
  DepositDataRegistry,
  EthVault,
  EthValidatorsChecker,
  IKeeperValidators,
  Keeper,
  VaultsRegistry,
} from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { expect } from './shared/expect'
import { setBalance, toHexString } from './shared/utils'
import {
  createEthValidatorsData,
  createValidatorsForValidatorsChecker,
  EthValidatorsData,
  exitSignatureIpfsHashes,
  getEthValidatorsSigningData,
  getValidatorProof,
  getValidatorsMultiProof,
  getWithdrawalCredentials,
  ValidatorsMultiProof,
  getEthValidatorsCheckerSigningData,
} from './shared/validators'
import {
  deployEthVaultV1,
  encodeEthVaultInitParams,
  ethVaultFixture,
  getOraclesSignatures,
} from './shared/fixtures'
import {
  MAX_UINT256,
  PANIC_CODES,
  VALIDATORS_DEADLINE,
  VALIDATORS_MIN_ORACLES,
  ZERO_ADDRESS,
  ZERO_BYTES32,
} from './shared/constants'
import { getEthVaultV1Factory } from './shared/contracts'
import keccak256 from 'keccak256'
import { signTypedData, SignTypedDataVersion } from '@metamask/eth-sig-util'

const gwei = 1000000000n
const uintSerializer = new UintNumberType(8)


describe('EthValidatorsChecker', () => {
  const validatorDeposit = ethers.parseEther('32')
  const capacity = MAX_UINT256
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  const deadline = VALIDATORS_DEADLINE

  let admin: Signer, other: Wallet, depositDataManager: Wallet, dao: Wallet, validatorsManager: Wallet,
    fakeValidatorsManager: Wallet
  let vault: EthVault,
    keeper: Keeper,
    validatorsRegistry: Contract,
    vaultsRegistry: VaultsRegistry,
    ethValidatorsChecker: EthValidatorsChecker,
    v1Vault: Contract,
    vaultNotDeposited: EthVault
  let validators: any[]
  let validatorsRegistryRoot: string

  before('deploy fixture', async () => {
    [dao, admin, other, depositDataManager] = await (ethers as any).getSigners()

    // privateKey attribute non-empty
    validatorsManager = new Wallet('0x798ce32ec683f3287dab0594b9ead26403a6da9c1d216d00e5aa088c9cf36864')
    fakeValidatorsManager = new Wallet('0xb4942e4f87ddfd23ddf833a47ebcf6bb37e0da344a2d6e229fd593c0b22bdb68')

    const fixture = await loadFixture(ethVaultFixture)
    validatorsRegistry = fixture.validatorsRegistry
    keeper = fixture.keeper
    ethValidatorsChecker = fixture.ethValidatorsChecker
    vaultsRegistry = fixture.vaultsRegistry

    vault = await fixture.createEthVault(admin, {
      capacity,
      feePercent,
      metadataIpfsHash,
    })
    await vault.connect(admin).setValidatorsManager(validatorsManager.address)
    v1Vault = await deployEthVaultV1(
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
    validators = await createValidatorsForValidatorsChecker()
    validatorsRegistryRoot = await validatorsRegistry.get_deposit_root()
    await vault.connect(other).deposit(other.address, ZERO_ADDRESS, { value: validatorDeposit })

    vaultNotDeposited = await fixture.createEthVault(admin, {
      capacity,
      feePercent,
      metadataIpfsHash,
    })
    await vaultNotDeposited.connect(other).deposit(
      other.address, 
      ZERO_ADDRESS,
      { value: ethers.parseEther('31') }
    )
  })

  describe('check validators manager signature', () => {
    it('fails for non-vault', async () => {
      await expect(
        ethValidatorsChecker.connect(admin).checkValidatorsManagerSignature(
          other.address,
          validatorsRegistryRoot,
          Buffer.from('', 'utf-8'),
          Buffer.from('', 'utf-8')
        )
      ).to.be.revertedWithCustomError(ethValidatorsChecker, 'InvalidVault')
    })

    it('fails for vault v1', async () => {
      await expect(
        ethValidatorsChecker.connect(admin).checkValidatorsManagerSignature(
          await v1Vault.getAddress(),
          validatorsRegistryRoot,
          Buffer.from('', 'utf-8'),
          Buffer.from('', 'utf-8')
        )
      ).to.be.revertedWithCustomError(ethValidatorsChecker, 'InvalidVault')
    })

    it('fails for vault not collateralized not deposited', async () => {      
      await expect(
        ethValidatorsChecker.connect(admin).checkValidatorsManagerSignature(
          await vaultNotDeposited.getAddress(),
          validatorsRegistryRoot,
          Buffer.from('', 'utf-8'),
          Buffer.from('', 'utf-8')
        )
      ).to.be.revertedWithCustomError(ethValidatorsChecker, 'AccessDenied')
    })

    it('fails for signer who is not validators manager', async () => {      
      const publicKeys: any[] = []
      for (let validator of validators) {
        publicKeys.push(validator.publicKey)
      }
      const vaultAddress = await vault.getAddress();
      const typedData = await getEthValidatorsCheckerSigningData(
        keccak256(Buffer.concat(publicKeys)),
        ethValidatorsChecker,
        vault,
        validatorsRegistryRoot,
      )
      const signature = signTypedData({
        privateKey: Buffer.from(ethers.getBytes(fakeValidatorsManager.privateKey)),
        data: typedData,
        version: SignTypedDataVersion.V4,
      })
      await expect(
        ethValidatorsChecker.connect(admin).checkValidatorsManagerSignature(
          vaultAddress,
          validatorsRegistryRoot,
          Buffer.concat(publicKeys),
          ethers.getBytes(signature)
        )
      ).to.be.revertedWithCustomError(ethValidatorsChecker, 'AccessDenied')
    })
  })

  it('succeeds', async () => {
    const publicKeys: any[] = []
    for (let validator of validators) {
      publicKeys.push(validator.publicKey)
    }
    const vaultAddress = await vault.getAddress();
    const typedData = await getEthValidatorsCheckerSigningData(
      Buffer.concat(publicKeys),
      ethValidatorsChecker,
      vault,
      validatorsRegistryRoot,
    )
    const signature = signTypedData({
      privateKey: Buffer.from(ethers.getBytes(validatorsManager.privateKey)),
      data: typedData,
      version: SignTypedDataVersion.V4,
    })

    await expect(
      ethValidatorsChecker.connect(admin).checkValidatorsManagerSignature(
        vaultAddress,
        validatorsRegistryRoot,
        Buffer.concat(publicKeys),
        ethers.getBytes(signature)
      )
    ).to.eventually.be.greaterThan(0)
  })

})
