import { ethers, waffle } from 'hardhat'
import { Contract, Wallet } from 'ethers'
import { hexlify } from 'ethers/lib/utils'
import { UintNumberType } from '@chainsafe/ssz'
import { MerkleTree } from 'merkletreejs'
import keccak256 from 'keccak256'
import { EthVault, IVaultFactory } from '../typechain-types'
import snapshotGasCost from './shared/snapshotGasCost'
import { ethVaultFixture } from './shared/fixtures'
import { expect } from './shared/expect'
import { setBalance } from './shared/utils'
import { appendDepositData, createValidators, getWithdrawalCredentials } from './shared/validators'

const createFixtureLoader = waffle.createFixtureLoader
const parseEther = ethers.utils.parseEther
const gwei = 1000000000
const uintSerializer = new UintNumberType(8)

type ThenArg<T> = T extends PromiseLike<infer U> ? U : T

describe('EthVault - register', () => {
  const validatorDeposit = parseEther('32')

  let keeper: Wallet, operator: Wallet, other: Wallet
  let vault: EthVault
  let validatorsRegistry: Contract
  let vaultParams: IVaultFactory.ParametersStruct
  let validators: Buffer[]
  let validatorsTree: MerkleTree
  let validator: Buffer
  let proof: string[]

  let loadFixture: ReturnType<typeof createFixtureLoader>
  let createVault: ThenArg<ReturnType<typeof ethVaultFixture>>['createVault']

  before('create fixture loader', async () => {
    ;[keeper, operator, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([keeper])
    vaultParams = {
      name: 'SW ETH Vault',
      symbol: 'SW-ETH-1',
      operator: operator.address,
      maxTotalAssets: parseEther('1000'),
      feePercent: 1000,
    }
  })

  beforeEach('deploy fixture', async () => {
    ;({ validatorsRegistry, createVault } = await loadFixture(ethVaultFixture))
    vault = await createVault(vaultParams)
    validators = await createValidators(validatorDeposit, vault.address)
    validatorsTree = new MerkleTree(validators, keccak256, {
      hashLeaves: true,
      sortPairs: true,
    })

    const val = validators[0]
    validator = appendDepositData(val, validatorDeposit, vault.address)
    proof = validatorsTree.getHexProof(keccak256(val))

    await vault.connect(other).deposit(other.address, { value: validatorDeposit })
    await vault.connect(operator).setValidatorsRoot(validatorsTree.getRoot(), 'new ipfs hash')
  })

  it('fails with not enough available assets', async () => {
    await setBalance(vault.address, parseEther('31.9'))
    await expect(vault.connect(keeper).registerValidator(validator, proof)).to.be.revertedWith(
      'InsufficientAvailableAssets()'
    )
  })

  it('fails with sender other than keeper', async () => {
    await expect(vault.connect(other).registerValidator(validator, proof)).to.be.revertedWith(
      'NotKeeper()'
    )
  })

  it('fails with invalid deposit data root', async () => {
    const invalidRoot = appendDepositData(validators[1], validatorDeposit, vault.address).subarray(
      144,
      176
    )
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
        .registerValidator(appendDepositData(validators[0], parseEther('1'), vault.address), proof)
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

  it('single validator', async () => {
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

  it('multiple validators', async () => {
    await setBalance(vault.address, validatorDeposit.mul(validators.length))

    for (let i = 0; i < validators.length; i++) {
      let val = validators[i]
      const proof = validatorsTree.getHexProof(keccak256(val))
      val = appendDepositData(val, validatorDeposit, vault.address)

      const receipt = await vault.connect(keeper).registerValidator(val, proof)
      const publicKey = hexlify(val.subarray(0, 48))
      await expect(receipt).to.emit(vault, 'ValidatorRegistered').withArgs(publicKey)
      await expect(receipt)
        .to.emit(validatorsRegistry, 'DepositEvent')
        .withArgs(
          publicKey,
          hexlify(getWithdrawalCredentials(vault.address)),
          hexlify(uintSerializer.serialize(validatorDeposit.div(gwei).toNumber())),
          hexlify(val.subarray(48, 144)),
          hexlify(uintSerializer.serialize(i))
        )
    }
  })
})
