// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {PriceFeed} from "../contracts/tokens/PriceFeed.sol";
import {IOsTokenVaultController} from "../contracts/interfaces/IOsTokenVaultController.sol";
import {IChainlinkAggregator} from "../contracts/interfaces/IChainlinkAggregator.sol";
import {IChainlinkV3Aggregator} from "../contracts/interfaces/IChainlinkV3Aggregator.sol";
import {IBalancerRateProvider} from "../contracts/interfaces/IBalancerRateProvider.sol";
import {EthHelpers} from "./helpers/EthHelpers.sol";

contract PriceFeedTest is Test, EthHelpers {
    // Test contracts
    PriceFeed public priceFeed;
    IOsTokenVaultController public osTokenVaultController;

    // Test addresses
    address public user;

    // Fork contracts
    ForkContracts public contracts;

    function setUp() public {
        // Activate Ethereum fork and get the contracts
        contracts = _activateEthereumFork();
        osTokenVaultController = contracts.osTokenVaultController;

        // Set up test accounts
        user = makeAddr("user");

        // Deploy the PriceFeed contract
        priceFeed = new PriceFeed(address(osTokenVaultController), "StakeWise osETH/ETH Price Feed");
    }

    // Test constructor and initialization
    function test_constructor() public view {
        assertEq(
            priceFeed.osTokenVaultController(),
            address(osTokenVaultController),
            "OsTokenVaultController address not set correctly"
        );
        assertEq(priceFeed.description(), "StakeWise osETH/ETH Price Feed", "Description not set correctly");
        assertEq(priceFeed.version(), 0, "Version should be 0");
    }

    // Test getRate function (Balancer interface)
    function test_getRate() public view {
        uint256 rate = priceFeed.getRate();

        // Get the expected rate directly from the vault controller
        uint256 expectedRate = osTokenVaultController.convertToAssets(10 ** priceFeed.decimals());

        assertEq(rate, expectedRate, "Rate should match osTokenVaultController.convertToAssets");
    }

    // Test getRate with gas snapshot
    function test_getRate_gas() public {
        _startSnapshotGas("PriceFeedTest_test_getRate_gas");
        priceFeed.getRate();
        _stopSnapshotGas();
    }

    // Test latestAnswer function (Chainlink interface)
    function test_latestAnswer() public view {
        int256 answer = priceFeed.latestAnswer();

        // Get the expected rate directly from the vault controller
        uint256 expectedRate = osTokenVaultController.convertToAssets(10 ** priceFeed.decimals());

        assertEq(answer, int256(expectedRate), "Answer should match the rate from getRate()");
    }

    // Test latestAnswer with gas snapshot
    function test_latestAnswer_gas() public {
        _startSnapshotGas("PriceFeedTest_test_latestAnswer_gas");
        priceFeed.latestAnswer();
        _stopSnapshotGas();
    }

    // Test latestTimestamp function
    function test_latestTimestamp() public view {
        uint256 timestamp = priceFeed.latestTimestamp();
        assertEq(timestamp, block.timestamp, "Timestamp should be the current block timestamp");
    }

    // Test decimals function
    function test_decimals() public view {
        uint8 dec = priceFeed.decimals();
        assertEq(dec, 18, "Decimals should be 18");
    }

    // Test latestRoundData function (Chainlink V3 interface)
    function test_latestRoundData() public view {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        // Check return values
        assertEq(roundId, 0, "RoundId should be 0");

        int256 expectedAnswer = priceFeed.latestAnswer();
        assertEq(answer, expectedAnswer, "Answer should match latestAnswer()");

        assertEq(startedAt, block.timestamp, "StartedAt should be current block timestamp");
        assertEq(updatedAt, block.timestamp, "UpdatedAt should be current block timestamp");
        assertEq(answeredInRound, 0, "AnsweredInRound should be 0");
    }

    // Test latestRoundData with gas snapshot
    function test_latestRoundData_gas() public {
        _startSnapshotGas("PriceFeedTest_test_latestRoundData_gas");
        priceFeed.latestRoundData();
        _stopSnapshotGas();
    }

    // Test consistency between different interface methods
    function test_interfaceConsistency() public view {
        uint256 balancerRate = priceFeed.getRate();
        int256 chainlinkAnswer = priceFeed.latestAnswer();

        assertEq(int256(balancerRate), chainlinkAnswer, "Balancer rate and Chainlink answer should be consistent");

        (, int256 roundDataAnswer,,,) = priceFeed.latestRoundData();

        assertEq(chainlinkAnswer, roundDataAnswer, "Chainlink answer and round data answer should be consistent");
    }

    // Test timestamp consistency across methods
    function test_timestampConsistency() public view {
        uint256 timestamp = priceFeed.latestTimestamp();

        (,, uint256 startedAt, uint256 updatedAt,) = priceFeed.latestRoundData();

        assertEq(timestamp, block.timestamp, "Timestamp from latestTimestamp should be block.timestamp");
        assertEq(startedAt, block.timestamp, "StartedAt should be block.timestamp");
        assertEq(updatedAt, block.timestamp, "UpdatedAt should be block.timestamp");
    }
}
