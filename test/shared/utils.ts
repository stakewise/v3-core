import { ECDSASignature, fromRpcSig } from 'ethereumjs-util'
import { signTypedData, SignTypedDataVersion, TypedDataUtils } from '@metamask/eth-sig-util'
import { ethers, waffle } from 'hardhat'
import { BigNumber } from 'ethers'
import { EIP712Domain } from './constants'

export const getSignatureFromTypedData = (privateKey: Buffer, data: any): ECDSASignature => {
  const signature = signTypedData({ privateKey, data, version: SignTypedDataVersion.V4 })
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
      { EIP712Domain },
      SignTypedDataVersion.V4
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
