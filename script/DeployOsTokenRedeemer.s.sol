// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console} from "forge-std/console.sol";
import {IOsTokenConfig} from "../contracts/interfaces/IOsTokenConfig.sol";
import {IOsTokenRedeemer} from "../contracts/interfaces/IOsTokenRedeemer.sol";
import {EthOsTokenRedeemer} from "../contracts/tokens/EthOsTokenRedeemer.sol";
import {GnoOsTokenRedeemer} from "../contracts/tokens/GnoOsTokenRedeemer.sol";

/**
 * @title DeployOsTokenRedeemer
 * @author StakeWise
 * @notice Deploys a new OsTokenRedeemer instance, updates the deployment addresses file
 *         and generates the governor transaction for setting the redeemer in OsTokenConfig
 */
contract DeployOsTokenRedeemer is Script {
    using stdJson for string;

    uint256 internal constant MAINNET = 1;
    uint256 internal constant HOODI = 560048;
    uint256 internal constant GNOSIS = 100;

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        console.log("Deploying from: ", vm.addr(privateKey));

        string memory networkName = _getNetworkName();
        string memory deploymentFilePath = string.concat("./deployments/", networkName, ".json");
        string memory deploymentData = vm.readFile(deploymentFilePath);
        address vaultsRegistry = deploymentData.readAddress(".VaultsRegistry");
        address osToken = deploymentData.readAddress(".OsToken");
        address osTokenVaultController = deploymentData.readAddress(".OsTokenVaultController");
        address osTokenConfig = deploymentData.readAddress(".OsTokenConfig");

        // reuse the owner and exit queue update delay of the redeemer currently set in OsTokenConfig
        address prevOsTokenRedeemer = IOsTokenConfig(osTokenConfig).redeemer();
        address owner = Ownable(prevOsTokenRedeemer).owner();
        uint256 exitQueueUpdateDelay = IOsTokenRedeemer(prevOsTokenRedeemer).exitQueueUpdateDelay();
        console.log("Previous OsTokenRedeemer: ", prevOsTokenRedeemer);
        console.log("Owner: ", owner);
        console.log("Exit queue update delay: ", exitQueueUpdateDelay);

        vm.startBroadcast(privateKey);
        address osTokenRedeemer;
        if (_isGnosisNetwork()) {
            osTokenRedeemer = address(
                new GnoOsTokenRedeemer(
                    vm.envAddress("GNO_TOKEN"),
                    vaultsRegistry,
                    osToken,
                    osTokenVaultController,
                    owner,
                    exitQueueUpdateDelay
                )
            );
        } else {
            osTokenRedeemer = address(
                new EthOsTokenRedeemer(vaultsRegistry, osToken, osTokenVaultController, owner, exitQueueUpdateDelay)
            );
        }
        vm.stopBroadcast();
        console.log("OsTokenRedeemer deployed at: ", osTokenRedeemer);

        // update only the OsTokenRedeemer address in the deployment file
        vm.writeJson(vm.toString(osTokenRedeemer), deploymentFilePath, ".OsTokenRedeemer");

        _generateGovernorTxJson(networkName, osTokenConfig, osTokenRedeemer);
    }

    function _generateGovernorTxJson(string memory networkName, address osTokenConfig, address osTokenRedeemer)
        private
    {
        string memory object = "setRedeemer";
        vm.serializeAddress(object, "to", osTokenConfig);
        vm.serializeString(object, "operation", "0");
        vm.serializeString(object, "method", "setRedeemer(address)");
        vm.serializeString(object, "value", "0.0");
        vm.serializeBytes(object, "data", abi.encodeCall(IOsTokenConfig.setRedeemer, (osTokenRedeemer)));

        address[] memory params = new address[](1);
        params[0] = osTokenRedeemer;
        string[] memory governorCalls = new string[](1);
        governorCalls[0] = vm.serializeAddress(object, "params", params);

        string memory output = vm.serializeString("governorCalls", "transactions", governorCalls);
        vm.writeJson(output, string.concat("./deployments/", networkName, "-governor-txs.json"));
    }

    function _getNetworkName() private view returns (string memory) {
        uint256 chainId = block.chainid;
        if (chainId == MAINNET) {
            return "mainnet";
        } else if (chainId == HOODI) {
            return "hoodi";
        } else if (chainId == GNOSIS) {
            return "gnosis";
        } else {
            revert("Unsupported chain ID");
        }
    }

    function _isGnosisNetwork() private view returns (bool) {
        return block.chainid == GNOSIS;
    }
}
