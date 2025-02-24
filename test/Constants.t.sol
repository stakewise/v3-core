pragma solidity ^0.8.22;

import {Test} from '../lib/forge-std/src/Test.sol';

abstract contract ConstantsTest is Test {
    address ZERO_ADDRESS;
    uint256 REWARDS_DELAY = 12 hours;
    uint256 SECURITY_DEPOSIT = 1 gwei;

    enum PanicCode {
      ARITHMETIC_UNDER_OR_OVERFLOW,
      DIVISION_BY_ZERO,
      OUT_OF_BOUND_INDEX
    }

    mapping(PanicCode => uint8) public panicCodes;

    function setUp() public virtual {
      panicCodes[PanicCode.ARITHMETIC_UNDER_OR_OVERFLOW] = 0x11;
      panicCodes[PanicCode.DIVISION_BY_ZERO] = 0x12;
      panicCodes[PanicCode.OUT_OF_BOUND_INDEX] = 0x32;
    }

    function expectRevertWithPanic(PanicCode code) public {
      vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", panicCodes[code]));
    }
}
