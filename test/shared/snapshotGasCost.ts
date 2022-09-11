import { TransactionReceipt, TransactionResponse } from '@ethersproject/abstract-provider'
import { BigNumber } from '@ethersproject/bignumber'
import { ContractTransaction } from '@ethersproject/contracts'
import { expect } from './expect'

const COVERAGE = process.env.COVERAGE === 'true'

// Inspired by https://github.com/Uniswap/snapshot-gas-cost
export default async function snapshotGasCost(
  x:
    | TransactionResponse
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
): Promise<void> {
  if (COVERAGE) return Promise.resolve()

  const unpromised = await x
  if (Array.isArray(unpromised)) {
    const unpromisedDeep = await Promise.all(unpromised.map(async (p) => await p))
    const waited = await Promise.all(unpromisedDeep.map(async (p) => p.wait()))
    expect({
      gasUsed: waited.reduce((m, v) => m + v.gasUsed.toNumber(), 0),
      calldataByteLength: unpromisedDeep.reduce((m, v) => m + v.data.length / 2 - 1, 0),
    }).toMatchSnapshot()
  } else if (typeof unpromised === 'number') {
    expect(unpromised).toMatchSnapshot()
  } else if ('wait' in unpromised) {
    const waited = await unpromised.wait()
    expect({
      gasUsed: waited.gasUsed.toNumber(),
      calldataByteLength: unpromised.data.length / 2 - 1,
    }).toMatchSnapshot()
  } else if (BigNumber.isBigNumber(unpromised)) {
    expect(unpromised.toNumber()).toMatchSnapshot()
  }
}
