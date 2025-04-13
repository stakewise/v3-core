// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

/**
 * @title IMerkleDistributor
 * @author StakeWise
 * @notice Defines the interface for the MerkleDistributor contract
 */
interface IMerkleDistributor {
    /**
     * @notice Distribute tokens one time
     * @param token The address of the token
     * @param amount The amount of tokens to distribute
     * @param rewardsIpfsHash The IPFS hash of the rewards
     * @param extraData The extra data for the distribution
     */
    function distributeOneTime(address token, uint256 amount, string calldata rewardsIpfsHash, bytes calldata extraData)
        external;

    /**
     * @notice Add or remove a distributor. Can only be called by the owner.
     * @param distributor The address of the distributor
     * @param isEnabled The status of the distributor, true for adding distributor, false for removing distributor
     */
    function setDistributor(address distributor, bool isEnabled) external;

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() external view returns (address);
}
