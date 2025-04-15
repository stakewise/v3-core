// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Network} from "./Network.sol";

contract ExecuteGovernorTxs is Network {
    using stdJson for string;

    struct Transaction {
        bytes data;
        string method;
    }

    function run() public {
        // Read and parse the JSON file
        string memory jsonString = vm.readFile(getGovernorTxsFilePath());
        console.log("JSON file loaded successfully");

        // Parse and extract transactions manually
        bytes memory transactionsRaw = jsonString.parseRaw(".transactions");
        Transaction[] memory transactions = abi.decode(transactionsRaw, (Transaction[]));

        uint256 txCount = transactions.length;
        console.log("Found %d transactions to execute", txCount);

        // Start broadcast with private key from environment variable
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address sender = vm.addr(privateKey);
        console.log("Executing transactions from address: %s", sender);

        Deployment memory deployment = getDeploymentData();

        vm.startBroadcast(privateKey);

        // Execute each transaction
        for (uint256 i = 0; i < txCount; i++) {
            Transaction memory transaction = transactions[i];

            console.log("Executing tx %d: %s", i, transaction.method);

            // Execute the transaction
            Address.functionCall(deployment.vaultsRegistry, transaction.data);
        }

        vm.stopBroadcast();
        console.log("All transactions processed");
    }
}
