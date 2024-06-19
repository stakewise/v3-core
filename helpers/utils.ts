import { Contract } from 'ethers'
import { HardhatRuntimeEnvironment } from 'hardhat/types/runtime'
import '@openzeppelin/hardhat-upgrades/dist/type-extensions'
import { GovernorCall } from './types'

export async function deployContract(
  hre: HardhatRuntimeEnvironment,
  contractName: string,
  constructorArgs: any[],
  path?: string,
  options?: any
): Promise<Contract> {
  const contract = await hre.ethers.deployContract(contractName, constructorArgs, options)
  await contract.waitForDeployment()

  const contractAddress = await contract.getAddress()
  console.log(`${contractName} deployed at`, contractAddress)
  if (path) {
    await verify(hre, contractAddress, constructorArgs, path)
  }
  return contract
}

export async function callContract(tx: any) {
  const result = await tx
  await result.wait()
}

async function delay(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

export async function verify(
  hre: HardhatRuntimeEnvironment,
  address: string,
  constructorArgs: any,
  contractPath: string
) {
  if (!process.env.BLOCK_EXPLORER_KEY) {
    return
  }

  let count = 0
  const maxTries = 8
  // eslint-disable-next-line no-constant-condition
  while (true) {
    await delay(10000)
    try {
      console.log('Verifying contract at', address)
      await hre.run('verify:verify', {
        address,
        constructorArguments: constructorArgs,
        contract: contractPath,
      })
      break
    } catch (error) {
      if (String(error).includes('Already Verified')) {
        console.log(`Already verified contract at ${contractPath} at address ${address}`)
        break
      }
      if (++count == maxTries) {
        console.log(
          `Failed to verify contract at ${contractPath} at address ${address}, error: ${error}`
        )
        break
      }
      console.log(`Retrying... Retry #${count}, last error: ${error}`)
    }
  }
}

export async function encodeGovernorContractCall(
  contract: Contract,
  method: string,
  params: any[]
): Promise<GovernorCall> {
  const data = contract.interface.encodeFunctionData(method, params)
  return {
    to: await contract.getAddress(),
    operation: '0',
    value: '0.0',
    data,
    method,
    params,
  }
}
