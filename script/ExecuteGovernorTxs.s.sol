// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Network} from "./Network.sol";

contract ExecuteGovernorTxs is Network {
    using stdJson for string;
    using Strings for uint256;

    function run() public {
        // Read and parse the JSON file
        string memory json = vm.readFile(getGovernorTxsFilePath());
        console.log("JSON file loaded successfully");

        // Parse and extract transactions count
        bytes[] memory transactions = abi.decode(json.parseRaw(".transactions"), (bytes[]));
        uint256 count = transactions.length;
        console.log("Found %d transactions to execute", count);

        // Start broadcast with private key from environment variable
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address sender = vm.addr(privateKey);
        console.log("Executing transactions from address: %s", sender);

        vm.startBroadcast();
        for (uint256 i = 0; i < count; i++) {
            // Construct JSON paths for 'to' and 'data'
            string memory idx = i.toString();
            string memory toPath = string.concat(".transactions[", idx, "].to");
            string memory dataPath = string.concat(".transactions[", idx, "].data");
            string memory methodPath = string.concat(".transactions[", idx, "].method");

            // Parse the target address, calldata and method
            address target = json.readAddress(toPath);
            bytes memory payload = json.readBytes(dataPath);
            string memory method = json.readString(methodPath);

            console.log("Executing tx %d: %s", i, method);

            // Execute the transaction
            Address.functionCall(target, payload);
        }

        vm.stopBroadcast();
        console.log("All transactions processed");
    }
}
