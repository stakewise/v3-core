// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IOsTokenFlashLoans} from "../interfaces/IOsTokenFlashLoans.sol";
import {IOsTokenFlashLoanRecipient} from "../interfaces/IOsTokenFlashLoanRecipient.sol";
import {IOsToken} from "../interfaces/IOsToken.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title OsTokenFlashLoans
 * @author StakeWise
 * @notice Mint and burn up to 100 000 osToken shares in single transaction.
 */
contract OsTokenFlashLoans is ReentrancyGuard, IOsTokenFlashLoans {
    uint256 private constant _maxFlashLoanAmount = 100_000 ether;
    address private immutable _osToken;

    /**
     * @dev Constructor
     * @param osToken The address of the OsToken contract
     */
    constructor(address osToken) ReentrancyGuard() {
        _osToken = osToken;
    }

    /// @inheritdoc IOsTokenFlashLoans
    // slither-disable-start reentrancy-balance
    function flashLoan(uint256 osTokenShares, bytes memory userData) external override nonReentrant {
        // check if not more than max flash loan amount requested
        if (osTokenShares == 0 || osTokenShares > _maxFlashLoanAmount) {
            revert Errors.InvalidShares();
        }

        // get current balance
        uint256 preLoanBalance = IERC20(_osToken).balanceOf(address(this));

        // mint OsToken shares for the caller
        IOsToken(_osToken).mint(msg.sender, osTokenShares);

        // execute callback
        IOsTokenFlashLoanRecipient(msg.sender).receiveFlashLoan(osTokenShares, userData);

        // get post loan balance
        uint256 postLoanBalance = IERC20(_osToken).balanceOf(address(this));

        // check if the amount was repaid
        if (postLoanBalance < preLoanBalance + osTokenShares) {
            revert Errors.FlashLoanFailed();
        }

        // burn OsToken shares
        IOsToken(address(_osToken)).burn(address(this), osTokenShares);

        // emit event
        emit OsTokenFlashLoan(msg.sender, osTokenShares);
    }
    // slither-disable-end reentrancy-balance
}
