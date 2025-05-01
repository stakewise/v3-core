// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";
import {IKeeperRewards} from "../contracts/interfaces/IKeeperRewards.sol";
import {EthMetaVault} from "../contracts/vaults/ethereum/custom/EthMetaVault.sol";
import {BalancedCurator} from "../contracts/curators/BalancedCurator.sol";
import {CuratorsRegistry} from "../contracts/curators/CuratorsRegistry.sol";
import {EthVault} from "../contracts/vaults/ethereum/EthVault.sol";
import {IEthVault} from "../contracts/interfaces/IEthVault.sol";
import {IEthMetaVault} from "../contracts/interfaces/IEthMetaVault.sol";

contract VaultSubVaultsTest is Test, EthHelpers {
    ForkContracts public contracts;
    EthMetaVault public metaVault;
    address public admin;
    address public curator;

    // Sub vaults
    address[] public subVaults;

    function setUp() public {
        // Activate fork and get contracts
        contracts = _activateEthereumFork();

        // Set up accounts
        admin = makeAddr("admin");
        vm.deal(admin, 100 ether);

        // Create a curator
        curator = address(new BalancedCurator());

        vm.prank(CuratorsRegistry(_curatorsRegistry).owner());
        CuratorsRegistry(_curatorsRegistry).addCurator(curator);

        // Deploy meta vault
        bytes memory initParams = abi.encode(
            IEthMetaVault.EthMetaVaultInitParams({
                admin: admin,
                subVaultsCurator: curator,
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );
        metaVault = EthMetaVault(payable(_getOrCreateVault(VaultType.EthMetaVault, admin, initParams, false)));

        // Deploy and add sub vaults
        for (uint256 i = 0; i < 3; i++) {
            address subVault = _createSubVault(admin);
            subVaults.push(subVault);

            vm.prank(admin);
            metaVault.addSubVault(subVault);
        }

        // Set curator for meta vault
        vm.prank(admin);
        metaVault.setSubVaultsCurator(curator);

        // Deposit funds to meta vault
        vm.deal(address(this), 10 ether);
        metaVault.deposit{value: 10 ether}(address(this), address(0));
    }

    function test_setSubVaultsCurator_notAdmin() internal {}
    function test_setSubVaultsCurator_zeroAddress() internal {}
    function test_setSubVaultsCurator_sameValue() internal {}
    function test_setSubVaultsCurator_notRegisteredCurator() internal {}
    function test_setSubVaultsCurator_success() internal {
        // check gas cost
        // check event emitted
    }

    function _createSubVault(address _admin) internal returns (address) {
        bytes memory initParams = abi.encode(
            IEthVault.EthVaultInitParams({
                capacity: 1000 ether,
                feePercent: 1000, // 10%
                metadataIpfsHash: "bafkreidivzimqfqtoqxkrpge6bjyhlvxqs3rhe73owtmdulaxr5do5in7u"
            })
        );

        return _createVault(VaultType.EthVault, _admin, initParams, false);
    }
}
