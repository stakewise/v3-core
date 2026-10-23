// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console} from "forge-std/console.sol";
import {IOsTokenConfig} from "../contracts/interfaces/IOsTokenConfig.sol";
import {IOsTokenRedeemer} from "../contracts/interfaces/IOsTokenRedeemer.sol";
import {EthOsTokenRedeemer} from "../contracts/tokens/EthOsTokenRedeemer.sol";
import {Network} from "./Network.sol";

contract UpgradeEthNetwork is Network {
    uint256 public constant MAX_REDEMPTION_FEE_PERCENT = 1000; // @dev 10.00 %

    address public osTokenRedeemer;

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address sender = vm.addr(privateKey);
        console.log("Deploying from: ", sender);

        Deployment memory deployment = getDeploymentData();

        // reuse the owner and exit queue update delay of the redeemer currently set in OsTokenConfig
        address prevOsTokenRedeemer = IOsTokenConfig(deployment.osTokenConfig).redeemer();
        address redeemerOwner = Ownable(prevOsTokenRedeemer).owner();
        uint256 exitQueueUpdateDelay = IOsTokenRedeemer(prevOsTokenRedeemer).exitQueueUpdateDelay();

        vm.startBroadcast(privateKey);

        // Deploy OsTokenRedeemer
        osTokenRedeemer = address(
            new EthOsTokenRedeemer(
                deployment.vaultsRegistry,
                deployment.osToken,
                deployment.osTokenVaultController,
                redeemerOwner,
                exitQueueUpdateDelay,
                MAX_REDEMPTION_FEE_PERCENT
            )
        );

        vm.stopBroadcast();

        generateGovernorTxJson(osTokenRedeemer);
        generateAddressesJson(osTokenRedeemer);
    }
}
