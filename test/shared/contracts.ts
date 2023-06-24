import { ContractFactory } from 'ethers'
import { ethers } from 'hardhat'
import { ethValidatorsRegistry } from '../../helpers/constants'

export async function getValidatorsRegistryFactory(): Promise<ContractFactory> {
  return await ethers.getContractFactory(ethValidatorsRegistry.abi, ethValidatorsRegistry.bytecode)
}
