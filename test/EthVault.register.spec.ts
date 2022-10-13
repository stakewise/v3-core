import { ethers, waffle } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { hexlify } from 'ethers/lib/utils'
import { UintNumberType } from '@chainsafe/ssz'
import { MerkleTree } from 'merkletreejs'
import keccak256 from 'keccak256'
import { EthVault } from '../typechain-types'
import { ThenArg } from '../helpers/types'
import snapshotGasCost from './shared/snapshotGasCost'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { setBalance } from './shared/utils'
import { appendDepositData, createValidators, getWithdrawalCredentials } from './shared/validators'

const createFixtureLoader = waffle.createFixtureLoader
const parseEther = ethers.utils.parseEther
const gwei = 1000000000
const uintSerializer = new UintNumberType(8)

describe('EthVault - register', () => {
  const validatorDeposit = parseEther('32')
  const maxTotalAssets = ethers.utils.parseEther('1000')
  const feePercent = 1000
  const vaultName = 'SW ETH Vault'
  const vaultSymbol = 'SW-ETH-1'
  let keeper: Wallet, operator: Wallet, registryOwner: Wallet, other: Wallet
  let vault: EthVault
  let validatorsRegistry: Contract
  let validators: Buffer[]
  let validatorsTree: MerkleTree

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createVault']

  before('create fixture loader', async () => {
    ;[keeper, operator, registryOwner, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([keeper, operator, registryOwner])
  })

  beforeEach('deploy fixture', async () => {
    ;({ validatorsRegistry, createVault } = await loadFixture(ethVaultFixture))
    vault = await createVault(vaultName, vaultSymbol, feePercent, maxTotalAssets)
    validators = await createValidators(validatorDeposit, vault.address)
    validatorsTree = new MerkleTree(validators, keccak256, {
      hashLeaves: true,
      sortPairs: true,
    })

    await vault.connect(other).deposit(other.address, { value: validatorDeposit })
    await vault.connect(operator).setValidatorsRoot(validatorsTree.getRoot(), 'new ipfs hash')
  })

  describe('single validator', () => {
    let validator: Buffer
    let proof: string[]

    beforeEach(async () => {
      const val = validators[0]
      validator = appendDepositData(val, validatorDeposit, vault.address)
      proof = validatorsTree.getHexProof(keccak256(val))
    })

    it('fails with not enough available assets', async () => {
      await setBalance(vault.address, parseEther('31.9'))
      await expect(vault.connect(keeper).registerValidator(validator, proof)).to.be.revertedWith(
        'InsufficientAvailableAssets()'
      )
    })

    it('fails with sender other than keeper', async () => {
      await expect(vault.connect(other).registerValidator(validator, proof)).to.be.revertedWith(
        'AccessDenied()'
      )
    })

    it('fails with invalid deposit data root', async () => {
      const invalidRoot = appendDepositData(
        validators[1],
        validatorDeposit,
        vault.address
      ).subarray(144, 176)
      await expect(
        vault.connect(keeper).registerValidator(Buffer.concat([validators[0], invalidRoot]), proof)
      ).to.be.revertedWith(
        'DepositContract: reconstructed DepositData does not match supplied deposit_data_root'
      )
    })

    it('fails with invalid deposit amount', async () => {
      await expect(
        vault
          .connect(keeper)
          .registerValidator(
            appendDepositData(validators[0], parseEther('1'), vault.address),
            proof
          )
      ).to.be.revertedWith(
        'DepositContract: reconstructed DepositData does not match supplied deposit_data_root'
      )
    })

    it('fails with invalid proof', async () => {
      const invalidProof = validatorsTree.getHexProof(validators[1])
      await expect(
        vault.connect(keeper).registerValidator(validator, invalidProof)
      ).to.be.revertedWith('InvalidValidator()')
    })

    it('fails with invalid validator length', async () => {
      await expect(
        vault
          .connect(keeper)
          .registerValidator(appendDepositData(validator, validatorDeposit, vault.address), proof)
      ).to.be.revertedWith('InvalidValidator()')
    })

    it('succeeds', async () => {
      const receipt = await vault.connect(keeper).registerValidator(validator, proof)
      const publicKey = hexlify(validator.subarray(0, 48))
      await expect(receipt).to.emit(vault, 'ValidatorRegistered').withArgs(publicKey)
      await expect(receipt)
        .to.emit(validatorsRegistry, 'DepositEvent')
        .withArgs(
          publicKey,
          hexlify(getWithdrawalCredentials(vault.address)),
          hexlify(uintSerializer.serialize(validatorDeposit.div(gwei).toNumber())),
          hexlify(validator.subarray(48, 144)),
          hexlify(uintSerializer.serialize(0))
        )
      await snapshotGasCost(receipt)
    })
  })

  describe('multiple validators', () => {
    let validatorsWithDepositData: Buffer[]
    let proofs: string[][]

    beforeEach(async () => {
      validatorsWithDepositData = []
      proofs = []
      for (let i = 0; i < validators.length; i++) {
        proofs.push(validatorsTree.getHexProof(keccak256(validators[i])))
        validatorsWithDepositData.push(
          appendDepositData(validators[i], validatorDeposit, vault.address)
        )
      }
      await setBalance(vault.address, validatorDeposit.mul(validators.length))
    })

    it('fails with not enough available assets', async () => {
      await setBalance(vault.address, parseEther('32').mul(validators.length - 1))
      await expect(
        vault.connect(keeper).registerValidators(validatorsWithDepositData, proofs)
      ).to.be.revertedWith('InsufficientAvailableAssets()')
    })

    it('fails with sender other than keeper', async () => {
      await expect(
        vault.connect(other).registerValidators(validatorsWithDepositData, proofs)
      ).to.be.revertedWith('AccessDenied()')
    })

    it('fails with invalid deposit data root', async () => {
      const invalidRoot = appendDepositData(
        validators[1],
        validatorDeposit,
        vault.address
      ).subarray(144, 176)
      validatorsWithDepositData[0] = Buffer.concat([validators[0], invalidRoot])
      await expect(
        vault.connect(keeper).registerValidators(validatorsWithDepositData, proofs)
      ).to.be.revertedWith(
        'DepositContract: reconstructed DepositData does not match supplied deposit_data_root'
      )
    })

    it('fails with invalid deposit amount', async () => {
      validatorsWithDepositData[0] = appendDepositData(
        validators[0],
        parseEther('1'),
        vault.address
      )
      await expect(
        vault.connect(keeper).registerValidators(validatorsWithDepositData, proofs)
      ).to.be.revertedWith(
        'DepositContract: reconstructed DepositData does not match supplied deposit_data_root'
      )
    })

    it('fails with invalid withdrawal credentials', async () => {
      validatorsWithDepositData[0] = appendDepositData(
        validators[0],
        validatorDeposit,
        keeper.address
      )
      await expect(
        vault.connect(keeper).registerValidators(validatorsWithDepositData, proofs)
      ).to.be.revertedWith(
        'DepositContract: reconstructed DepositData does not match supplied deposit_data_root'
      )
    })

    it('fails with invalid proof', async () => {
      proofs[0] = validatorsTree.getHexProof(validators[1])
      await expect(
        vault.connect(keeper).registerValidators(validatorsWithDepositData, proofs)
      ).to.be.revertedWith('InvalidValidator()')
    })

    it('fails with invalid validator length', async () => {
      validatorsWithDepositData[0] = appendDepositData(
        validatorsWithDepositData[0],
        validatorDeposit,
        vault.address
      )
      await expect(
        vault.connect(keeper).registerValidators(validatorsWithDepositData, proofs)
      ).to.be.revertedWith('InvalidValidator()')
    })

    it('fails with invalid proofs length', async () => {
      proofs.push(validatorsTree.getHexProof(keccak256(validators[0])))
      await expect(
        vault.connect(keeper).registerValidators(validatorsWithDepositData, proofs)
      ).to.be.revertedWith('InvalidProofsLength()')
    })

    it('succeeds', async () => {
      const receipt = await vault
        .connect(keeper)
        .registerValidators(validatorsWithDepositData, proofs)
      for (let i = 0; i < validators.length; i++) {
        const validator = validators[i]
        const publicKey = hexlify(validator.subarray(0, 48))
        await expect(receipt).to.emit(vault, 'ValidatorRegistered').withArgs(publicKey)
        await expect(receipt)
          .to.emit(validatorsRegistry, 'DepositEvent')
          .withArgs(
            publicKey,
            hexlify(getWithdrawalCredentials(vault.address)),
            hexlify(uintSerializer.serialize(validatorDeposit.div(gwei).toNumber())),
            hexlify(validator.subarray(48, 144)),
            hexlify(uintSerializer.serialize(i))
          )
      }
      await snapshotGasCost(receipt)
    })
  })
})
