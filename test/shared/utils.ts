import { signTypedData_v4, TypedDataUtils } from 'eth-sig-util'
import { ECDSASignature, fromRpcSig } from 'ethereumjs-util'
import { ethers, waffle } from 'hardhat'
import { BigNumber } from 'ethers'
import { EIP712Domain } from './constants'

export const getSignatureFromTypedData = (
  privateKey: Buffer,
  typedData: any // TODO: should be TypedData, from eth-sig-utils, but TS doesn't accept it
): ECDSASignature => {
  const signature = signTypedData_v4(privateKey, {
    data: typedData,
  })
  return fromRpcSig(signature)
}

export async function domainSeparator(name, version, chainId, verifyingContract) {
  return (
    '0x' +
    TypedDataUtils.hashStruct(
      'EIP712Domain',
      {
        name,
        version,
        chainId,
        verifyingContract,
      },
      { EIP712Domain }
    ).toString('hex')
  )
}

export async function latestTimestamp(): Promise<BigNumber> {
  const block = await ethers.provider.getBlock('latest')
  return BigNumber.from(block.timestamp)
}

export async function setBalance(address: string, value: BigNumber): Promise<void> {
  return waffle.provider.send('hardhat_setBalance', [
    address,
    value.toHexString().replace('0x0', '0x'),
  ])
}

export async function increaseTime(seconds: number): Promise<void> {
  await waffle.provider.send('evm_increaseTime', [seconds])
  return waffle.provider.send('evm_mine', [])
}
