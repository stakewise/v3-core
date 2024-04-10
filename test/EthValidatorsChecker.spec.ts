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

const gwei = 1000000000n
const uintSerializer = new UintNumberType(8)


describe('EthValidatorsChecker', () => {
  const validatorDeposit = ethers.parseEther('32')
  const capacity = MAX_UINT256
  const feePercent = 1000
  const metadataIpfsHash = 'bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u'
  const deadline = VALIDATORS_DEADLINE

  let admin: Signer, other: Wallet, depositDataManager: Wallet, dao: Wallet, validatorsManager: Wallet
  let vault: EthVault,
    keeper: Keeper,
    validatorsRegistry: Contract,
    vaultsRegistry: VaultsRegistry,
    ethValidatorsChecker: EthValidatorsChecker,
    v1Vault: Contract,
    vaultNotDeposited: EthVault
  let validators: any[]
  let validatorsRegistryRoot: string

  before('create fixture loader', async () => {
    ;[dao, admin, other, depositDataManager, validatorsManager] = await (ethers as any).getSigners()
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
    console.log('validatorsManager.address %s', validatorsManager.address)
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

    it('fails with wrong signature', async () => {
      const abiCoder = ethers.AbiCoder.defaultAbiCoder()
      
      const publicKeys: any[] = []
      for (let validator of validators) {
        publicKeys.push(validator.publicKey)
      }
      const message = keccak256(
        abiCoder.encode([
          'bytes32', 'bytes32', 'address'
        ],[
          validatorsRegistryRoot,
          keccak256(Buffer.concat(publicKeys)),
          await vault.getAddress()
        ])
      )
      const signature = await other.signMessage(message)
      await expect(
        ethValidatorsChecker.connect(admin).checkValidatorsManagerSignature(
          await vault.getAddress(),
          validatorsRegistryRoot,
          Buffer.concat(publicKeys),
          ethers.getBytes(signature)
        )
      ).to.be.revertedWithCustomError(ethValidatorsChecker, 'AccessDenied')
    })
  })

  it('succeeds 1', async () => {
    const abiCoder = ethers.AbiCoder.defaultAbiCoder()
    
    const publicKeys: any[] = []
    for (let validator of validators) {
      publicKeys.push(validator.publicKey)
    }
    const vaultAddress = await vault.getAddress();
    const message = keccak256(
        abiCoder.encode([
        'bytes32', 'bytes32', 'address'
      ],[
        validatorsRegistryRoot,
        keccak256(Buffer.concat(publicKeys)),
        vaultAddress
      ])
    )
    const signature = await validatorsManager.signMessage(message)

    console.log('test signature %s', signature)
    console.log('test message hash %s', message.toString('hex'))
    console.log('test: vaultAddress %s', vaultAddress)

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
