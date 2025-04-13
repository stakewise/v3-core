// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Multicall} from "../base/Multicall.sol";

contract MulticallMock is Multicall {
    uint256 public value;
    string public message;
    bool public flag;
    address public caller;

    function setValue(uint256 _value) external returns (uint256) {
        value = _value;
        return value;
    }

    function setMessage(string calldata _message) external returns (string memory) {
        message = _message;
        return message;
    }

    function setFlag(bool _flag) external returns (bool) {
        flag = _flag;
        return flag;
    }

    function revertWithMessage() external pure {
        revert("Intentional revert with message");
    }

    function revertWithoutMessage() external pure {
        revert();
    }

    function multipleParams(uint256 a, string calldata b, bool c) external returns (uint256, string memory, bool) {
        value = a;
        message = b;
        flag = c;
        return (a, b, c);
    }

    function checkCaller() external returns (address) {
        caller = msg.sender;
        return caller;
    }

    function addToValue(uint256 amount) external returns (uint256) {
        value += amount;
        return value;
    }
}
