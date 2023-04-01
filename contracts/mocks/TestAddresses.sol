// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.18;
import 'hardhat/console.sol';

contract TestAddresses {
  function compare(address x1, address x2) external view returns (bool) {
    console.log(uint160(x1) > uint160(x2));
    return x1 > x2;
  }
}
