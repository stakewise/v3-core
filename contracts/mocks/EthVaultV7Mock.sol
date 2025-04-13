// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IEthVault} from "../interfaces/IEthVault.sol";
import {EthVaultV6Mock} from "./EthVaultV6Mock.sol";

contract EthVaultV7Mock is EthVaultV6Mock {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IEthVault.EthVaultConstructorArgs memory args) EthVaultV6Mock(args) {}

    function initialize(bytes calldata data) external payable override reinitializer(7) {}

    function version() public pure virtual override returns (uint8) {
        return 7;
    }
}
