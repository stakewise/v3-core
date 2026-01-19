// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Packing} from "@openzeppelin/contracts/utils/Packing.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {Errors} from "./Errors.sol";

/**
 * @title SubVaultExits
 * @author StakeWise
 * @notice Includes the common functionality for managing the meta vault sub-vaults exits
 */
library SubVaultExits {
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    /**
     * @dev Fetches the sub-vault exit data
     * @param subVaultsExits The mapping of sub-vault exits queues
     * @param vault The address of the sub-vault
     * @return positionTicket The position ticket of the sub-vault
     * @return shares The shares to be exited from the sub-vault
     */
    function peekSubVaultExit(
        mapping(address vault => DoubleEndedQueue.Bytes32Deque) storage subVaultsExits,
        address vault
    ) internal view returns (uint160 positionTicket, uint96 shares) {
        if (subVaultsExits[vault].empty()) {
            return (0, 0);
        }
        bytes32 packed = subVaultsExits[vault].front();
        positionTicket = uint160(Packing.extract_32_20(packed, 0));
        shares = uint96(Packing.extract_32_12(packed, 20));
    }

    /**
     * @dev Stores the sub-vault exit data
     * @param subVaultsExits The mapping of sub-vault exits queues
     * @param vault The address of the sub-vault
     * @param positionTicket The position ticket of the sub-vault
     * @param shares The shares to be exited from the sub-vault
     * @param front Whether to insert the exit data at the front of the queue
     */
    function pushSubVaultExit(
        mapping(address vault => DoubleEndedQueue.Bytes32Deque) storage subVaultsExits,
        address vault,
        uint160 positionTicket,
        uint96 shares,
        bool front
    ) internal {
        if (shares == 0) revert Errors.InvalidShares();
        bytes32 packed = Packing.pack_20_12(bytes20(positionTicket), bytes12(shares));
        if (front) {
            subVaultsExits[vault].pushFront(packed);
        } else {
            subVaultsExits[vault].pushBack(packed);
        }
    }

    /**
     * @dev Removes the sub-vault exit data
     * @param subVaultsExits The mapping of sub-vault exits queues
     * @param vault The address of the sub-vault
     * @return positionTicket The position ticket of the sub-vault
     * @return shares The shares to be exited from the sub-vault
     */
    function popSubVaultExit(
        mapping(address vault => DoubleEndedQueue.Bytes32Deque) storage subVaultsExits,
        address vault
    ) internal returns (uint160 positionTicket, uint96 shares) {
        bytes32 packed = subVaultsExits[vault].popFront();
        positionTicket = uint160(Packing.extract_32_20(packed, 0));
        shares = uint96(Packing.extract_32_12(packed, 20));
    }
}
