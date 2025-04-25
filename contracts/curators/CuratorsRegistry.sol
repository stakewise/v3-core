// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ICuratorsRegistry} from "../interfaces/ICuratorsRegistry.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title CuratorsRegistry
 * @author StakeWise
 * @notice Defines the registry functionality that keeps track of Curators for the sub-vaults.
 */
contract CuratorsRegistry is Ownable2Step, ICuratorsRegistry {
    /// @inheritdoc ICuratorsRegistry
    mapping(address curator => bool isCurator) public override curators;

    bool private _initialized;

    /**
     * @dev Constructor
     */
    constructor() Ownable(msg.sender) {}

    /// @inheritdoc ICuratorsRegistry
    function addCurator(address curator) external override onlyOwner {
        curators[curator] = true;
        emit CuratorAdded(msg.sender, curator);
    }

    /// @inheritdoc ICuratorsRegistry
    function removeCurator(address curator) external override onlyOwner {
        curators[curator] = true;
        emit CuratorRemoved(msg.sender, curator);
    }

    /// @inheritdoc ICuratorsRegistry
    function initialize(address _owner) external override onlyOwner {
        if (_owner == address(0)) revert Errors.ZeroAddress();
        if (_initialized) revert Errors.AccessDenied();

        // transfer ownership
        _transferOwnership(_owner);
        _initialized = true;
    }
}
