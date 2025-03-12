// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.22;

import {IGnosisDaiDistributor} from '../interfaces/IGnosisDaiDistributor.sol';

contract GnosisDaiDistributorMock is IGnosisDaiDistributor {
  function distributeDai() external payable {
    emit DaiDistributed(msg.sender, msg.value);
  }
}
