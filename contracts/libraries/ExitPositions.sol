// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Packing} from "@openzeppelin/contracts/utils/Packing.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {Errors} from "./Errors.sol";

/**
 * @title ExitPositions
 * @author StakeWise
 * @notice Includes the common functionality for managing exit positions in queues
 */
library ExitPositions {
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    /**
     * @dev Fetches the exit data from a mapping-based queue
     * @param exits The mapping of exit queues
     * @param vault The address of the vault
     * @return positionTicket The position ticket
     * @return shares The shares to be exited
     */
    function peek(mapping(address vault => DoubleEndedQueue.Bytes32Deque) storage exits, address vault)
        internal
        view
        returns (uint160 positionTicket, uint96 shares)
    {
        if (exits[vault].empty()) {
            return (0, 0);
        }
        bytes32 packed = exits[vault].front();
        positionTicket = uint160(Packing.extract_32_20(packed, 0));
        shares = uint96(Packing.extract_32_12(packed, 20));
    }

    /**
     * @dev Stores exit data in a mapping-based queue
     * @param exits The mapping of exit queues
     * @param vault The address of the vault
     * @param positionTicket The position ticket
     * @param shares The shares to be exited
     * @param front Whether to insert the exit data at the front of the queue
     */
    function push(
        mapping(address vault => DoubleEndedQueue.Bytes32Deque) storage exits,
        address vault,
        uint160 positionTicket,
        uint96 shares,
        bool front
    ) internal {
        if (shares == 0) revert Errors.InvalidShares();
        bytes32 packed = Packing.pack_20_12(bytes20(positionTicket), bytes12(shares));
        if (front) {
            exits[vault].pushFront(packed);
        } else {
            exits[vault].pushBack(packed);
        }
    }

    /**
     * @dev Removes and returns exit data from a mapping-based queue
     * @param exits The mapping of exit queues
     * @param vault The address of the vault
     * @return positionTicket The position ticket
     * @return shares The shares to be exited
     */
    function pop(mapping(address vault => DoubleEndedQueue.Bytes32Deque) storage exits, address vault)
        internal
        returns (uint160 positionTicket, uint96 shares)
    {
        bytes32 packed = exits[vault].popFront();
        positionTicket = uint160(Packing.extract_32_20(packed, 0));
        shares = uint96(Packing.extract_32_12(packed, 20));
    }
}
