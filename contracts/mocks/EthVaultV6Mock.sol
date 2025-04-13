// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {EthVault, IEthVault} from "../vaults/ethereum/EthVault.sol";

contract EthVaultV6Mock is EthVault {
    uint128 public newVar;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IEthVault.EthVaultConstructorArgs memory args) EthVault(args) {}

    function initialize(bytes calldata data) external payable virtual override reinitializer(6) {
        (newVar) = abi.decode(data, (uint128));
    }

    function somethingNew() external pure returns (bool) {
        return true;
    }

    function version() public pure virtual override returns (uint8) {
        return 6;
    }
}
