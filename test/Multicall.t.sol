// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {MulticallMock} from "../contracts/mocks/MulticallMock.sol";

contract MulticallTest is Test {
    MulticallMock public multicall;

    function setUp() public {
        multicall = new MulticallMock();
    }

    function test_multipleSuccessfulCalls() public {
        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeWithSelector(multicall.setValue.selector, 123);
        data[1] = abi.encodeWithSelector(multicall.setMessage.selector, "Hello, Multicall");
        data[2] = abi.encodeWithSelector(multicall.setFlag.selector, true);

        bytes[] memory results = multicall.multicall(data);

        assertEq(results.length, 3);
        assertEq(abi.decode(results[0], (uint256)), 123);
        assertEq(abi.decode(results[1], (string)), "Hello, Multicall");
        assertEq(abi.decode(results[2], (bool)), true);

        assertEq(multicall.value(), 123);
        assertEq(multicall.message(), "Hello, Multicall");
        assertEq(multicall.flag(), true);
    }

    function test_emptyCallsArray() public {
        bytes[] memory data = new bytes[](0);
        bytes[] memory results = multicall.multicall(data);

        assertEq(results.length, 0);
    }

    function test_multipleParams() public {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSelector(multicall.multipleParams.selector, 456, "Multiple params", false);

        bytes[] memory results = multicall.multicall(data);

        assertEq(results.length, 1);
        (uint256 a, string memory b, bool c) = abi.decode(results[0], (uint256, string, bool));
        assertEq(a, 456);
        assertEq(b, "Multiple params");
        assertEq(c, false);

        assertEq(multicall.value(), 456);
        assertEq(multicall.message(), "Multiple params");
        assertEq(multicall.flag(), false);
    }

    function test_revertWithMessage() public {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSelector(multicall.revertWithMessage.selector);

        vm.expectRevert("Intentional revert with message");
        multicall.multicall(data);
    }

    function test_revertWithoutMessage() public {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSelector(multicall.revertWithoutMessage.selector);

        vm.expectRevert();
        multicall.multicall(data);
    }

    function test_invalidCalldata() public {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodePacked("invalidCalldata");

        vm.expectRevert();
        multicall.multicall(data);
    }

    function test_mixSuccessAndFailure() public {
        // First set a value that should remain after the revert
        multicall.setValue(42);

        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeWithSelector(multicall.setValue.selector, 789);
        data[1] = abi.encodeWithSelector(multicall.revertWithMessage.selector);
        data[2] = abi.encodeWithSelector(multicall.setFlag.selector, true);

        vm.expectRevert("Intentional revert with message");
        multicall.multicall(data);

        // Check that the initial value remains since the entire multicall reverted
        assertEq(multicall.value(), 42);
        // The flag should not be set either
        assertEq(multicall.flag(), false);
    }

    function test_delegateCall() public {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSelector(multicall.checkCaller.selector);

        bytes[] memory results = multicall.multicall(data);

        // The caller should be this test contract, not the multicall contract
        assertEq(abi.decode(results[0], (address)), address(this));
        assertEq(multicall.caller(), address(this));
    }

    function testSequentialExecution() public {
        // Add a function to the mock contract that increments the current value
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(multicall.setValue.selector, 100);
        // For the second call, we'll manually encode a call that adds 50 to whatever the current value is
        data[1] = abi.encodeWithSignature("addToValue(uint256)", 50);

        bytes[] memory results = multicall.multicall(data);

        assertEq(abi.decode(results[0], (uint256)), 100);
        assertEq(abi.decode(results[1], (uint256)), 150);
        assertEq(multicall.value(), 150);
    }

    function test_largeNumberOfCalls() public {
        uint256 numCalls = 20;
        bytes[] memory data = new bytes[](numCalls);

        for (uint256 i = 0; i < numCalls; i++) {
            data[i] = abi.encodeWithSelector(multicall.setValue.selector, i);
        }

        bytes[] memory results = multicall.multicall(data);

        assertEq(results.length, numCalls);
        for (uint256 i = 0; i < numCalls; i++) {
            assertEq(abi.decode(results[i], (uint256)), i);
        }

        // Value should be set to the last call's argument
        assertEq(multicall.value(), numCalls - 1);
    }
}
