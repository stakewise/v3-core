// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Network} from "./Network.sol";

contract ExecuteGovernorTxs is Network {
    using stdJson for string;

    function run() public {
        // Read and parse the JSON file
        string memory jsonString = vm.readFile(getGovernorTxsFilePath());

        // Get the number of transactions
        uint256 txCount = jsonString.readUint(".transactions.length");

        // Start broadcast with private key from environment variable
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address sender = vm.addr(privateKey);
        console.log("Executing transactions from address: %s", sender);

        vm.startBroadcast(privateKey);

        console.log("Found %d transactions to execute", txCount);

        // Execute each transaction
        for (uint256 i = 0; i < txCount; i++) {
            string memory txPath = string.concat(".transactions[", vm.toString(i), "]");

            // Extract transaction data
            bytes memory data = jsonString.readBytes(string.concat(txPath, ".data"));
            address to = jsonString.readAddress(string.concat(txPath, ".to"));
            string memory method = jsonString.readString(string.concat(txPath, ".method"));

            console.log("Executing tx %d: %s to %s", i, method, to);

            // Execute the transaction
            (bool success,) = to.call(data);

            if (success) {
                console.log("Transaction succeeded");
            } else {
                console.log("Transaction failed");
                revert("Transaction execution failed");
            }
        }

        vm.stopBroadcast();
        console.log("All transactions executed successfully");
    }
}
