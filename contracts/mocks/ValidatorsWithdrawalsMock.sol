// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.22;

contract ValidatorsWithdrawalsMock {
    error InvalidFeeError();

    event ValidatorWithdrawn(address sender, bytes fromPubkey, uint64 amount);

    uint256 private constant _fee = 0.1 ether;

    fallback(bytes calldata input) external payable returns (bytes memory output) {
        if (input.length == 0) {
            return abi.encode(_fee);
        }
        if (msg.value != _fee) {
            revert InvalidFeeError();
        }

        emit ValidatorWithdrawn(msg.sender, input[:48], uint64(bytes8(input[48:56])));
        return "";
    }
}
