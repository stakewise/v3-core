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
  createValidatorsForValidatorsManager,
  EthValidatorsData,
  exitSignatureIpfsHashes,
  getEthValidatorsSigningData,
  getValidatorProof,
  getValidatorsMultiProof,
  getWithdrawalCredentials,
  ValidatorsMultiProof,
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

const gwei = 1000000000n
const uintSerializer = new UintNumberType(8)


describe('EthValidatorsChecker', () => {
  const validatorDeposit = ethers.parseEther('32')
  const capacity = MAX_UINT256
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  const deadline = VALIDATORS_DEADLINE

  let admin: Signer, other: Wallet, manager: Wallet, dao: Wallet
  let vault: EthVault,
    keeper: Keeper,
    validatorsRegistry: Contract,
    vaultsRegistry: VaultsRegistry,
    ethValidatorsChecker: EthValidatorsChecker,
    v1Vault: Contract,
    vaultNotDeposited: EthVault
  let validatorsForValidatorsManager: Buffer
  let validatorsRegistryRoot: string

  before('create fixture loader', async () => {
    ;[dao, admin, other, manager] = await (ethers as any).getSigners()
  })

  before('deploy fixture', async () => {
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
    validatorsForValidatorsManager = await createValidatorsForValidatorsManager()
    validatorsRegistryRoot = await validatorsRegistry.get_deposit_root()
    await vault.connect(other).deposit(other.address, ZERO_ADDRESS, { value: validatorDeposit })

    vaultNotDeposited = await fixture.createEthVault(admin, {
      capacity,
      feePercent,
      metadataIpfsHash,
    })
    // await vaultsRegistry.addVault(await vaultNotDeposited.getAddress())
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
  })


})
