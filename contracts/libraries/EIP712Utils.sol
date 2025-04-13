// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

/**
 * @title EIP712Utils
 * @author StakeWise
 * @notice Includes functionality for calculating EIP712 hashes
 */
library EIP712Utils {
    /**
     * @notice Computes the hash of the EIP712 typed data
     * @dev This function is used to compute the hash of the EIP712 typed data
     * @param name The name of the domain
     * @param verifyingContract The address of the verifying contract
     * @return The hash of the EIP712 typed data
     */
    function computeDomainSeparator(string memory name, address verifyingContract) external view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256("1"),
                block.chainid,
                verifyingContract
            )
        );
    }
}
