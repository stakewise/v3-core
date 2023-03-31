// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

error DepositFailed();

contract DepositorMock {
  address public immutable vault;

  constructor(address _vault) {
    vault = _vault;
  }

  function depositToVault() public payable {
    (bool success, ) = vault.call{value: msg.value}('');
    if (!success) revert DepositFailed();
  }
}
