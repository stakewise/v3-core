import { TransactionReceipt, TransactionResponse } from '@ethersproject/abstract-provider'
import { BigNumber } from '@ethersproject/bignumber'
import { ContractTransaction } from '@ethersproject/contracts'
import { ContractTransactionResponse } from 'ethers'
import { expect } from './expect'
import { MAINNET_FORK } from '../../helpers/constants'

const COVERAGE = process.env.COVERAGE === 'true'

// Inspired by https://github.com/Uniswap/snapshot-gas-cost
export default async function snapshotGasCost(
  x:
    | TransactionResponse
    | ContractTransactionResponse
    | Promise<ContractTransactionResponse>
    | Promise<TransactionResponse>
    | TransactionResponse[]
    | Promise<TransactionResponse>[]
    | ContractTransaction
    | Promise<ContractTransaction>
    | TransactionReceipt
    | Promise<BigNumber>
    | BigNumber
    | Promise<number>
    | number
    | bigint
): Promise<void> {
  if (COVERAGE || MAINNET_FORK.enabled) return Promise.resolve()

  const unpromised = await x
  if (Array.isArray(unpromised)) {
    const unpromisedDeep = await Promise.all(unpromised.map(async (p) => await p))
    const waited = await Promise.all(unpromisedDeep.map(async (p) => p.wait()))
    expect({
      gasUsed: waited.reduce((m, v) => m + Number(v.gasUsed), 0),
      calldataByteLength: unpromisedDeep.reduce((m, v) => m + v.data.length / 2 - 1, 0),
    }).toMatchSnapshot()
  } else if (typeof unpromised === 'number') {
    expect(unpromised).toMatchSnapshot()
  } else if (typeof unpromised === 'bigint') {
    expect(Number(unpromised)).toMatchSnapshot()
  } else if ('wait' in unpromised) {
    const waited = (await unpromised.wait()) as TransactionReceipt
    expect({
      gasUsed: Number(waited.gasUsed),
      calldataByteLength: unpromised.data.length / 2 - 1,
    }).toMatchSnapshot()
  } else if (BigNumber.isBigNumber(unpromised)) {
    expect(Number(unpromised)).toMatchSnapshot()
  }
}
