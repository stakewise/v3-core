// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOsTokenFlashLoanRecipient} from "../interfaces/IOsTokenFlashLoanRecipient.sol";
import {IOsTokenFlashLoans} from "../interfaces/IOsTokenFlashLoans.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title OsTokenFlashLoanRecipientMock
 * @notice Mock contract that acts both as the caller and receiver of the flash loan
 */
contract OsTokenFlashLoanRecipientMock is IOsTokenFlashLoanRecipient {
    address public osToken;
    bool public shouldRepayLoan; // Simulate success or failure in repaying the loan
    address public flashLoanContract;

    /**
     * @dev Constructor to set the osToken address and flash loan contract
     * @param _osToken The address of the OsToken contract
     * @param _flashLoanContract The address of the OsTokenFlashLoans contract
     */
    constructor(address _osToken, address _flashLoanContract) {
        osToken = _osToken;
        flashLoanContract = _flashLoanContract;
        shouldRepayLoan = true; // Default to repaying the loan
    }

    function receiveFlashLoan(uint256 osTokenShares, bytes calldata) external override {
        require(msg.sender == flashLoanContract, "Caller is not flash loan contract");

        // Do something with the userData if needed

        // If the recipient is supposed to repay the loan
        if (shouldRepayLoan) {
            // Repay the loan by transferring back the borrowed osTokenShares
            IERC20(osToken).transfer(msg.sender, osTokenShares);
        }
        // If shouldRepayLoan is false, we simulate a failure by not transferring back the tokens
    }

    /**
     * @notice Executes a flash loan from the OsTokenFlashLoans contract
     * @param osTokenShares The amount of OsToken shares to borrow
     * @param userData Arbitrary data to pass along with the flash loan
     */
    function executeFlashLoan(uint256 osTokenShares, bytes calldata userData) external {
        IOsTokenFlashLoans(flashLoanContract).flashLoan(osTokenShares, userData);
    }

    /**
     * @notice Toggle the loan repayment behavior (for testing)
     * @param repay Set to true if the loan should be repaid, false otherwise
     */
    function setShouldRepayLoan(bool repay) external {
        shouldRepayLoan = repay;
    }
}
