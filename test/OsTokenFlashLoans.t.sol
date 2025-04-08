// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {Test} from 'forge-std/Test.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {OsTokenFlashLoans, IOsTokenFlashLoans} from '../contracts/tokens/OsTokenFlashLoans.sol';
import {OsTokenFlashLoanRecipientMock} from '../contracts/mocks/OsTokenFlashLoanRecipientMock.sol';
import {OsToken} from '../contracts/tokens/OsToken.sol';
import {IOsTokenFlashLoanRecipient} from '../contracts/interfaces/IOsTokenFlashLoanRecipient.sol';
import {Errors} from '../contracts/libraries/Errors.sol';
import {EthHelpers} from './helpers/EthHelpers.sol';

contract OsTokenFlashLoansTest is Test, EthHelpers {
  // Constants for deployed contracts
  uint256 public constant MAX_FLASH_LOAN_AMOUNT = 100_000 ether;

  ForkContracts public contracts;

  // Contract instances
  OsTokenFlashLoans public flashLoans;
  OsToken public osToken;
  OsTokenFlashLoanRecipientMock public recipient;

  // Test accounts
  address public admin;
  address public user;

  function setUp() public {
    // Fork mainnet
    contracts = _activateEthereumFork();

    // Connect to deployed contracts
    flashLoans = OsTokenFlashLoans(_osTokenFlashLoans);
    osToken = OsToken(_osToken);

    // Set up test accounts
    admin = makeAddr('admin');
    user = makeAddr('user');
    vm.deal(user, 100 ether);

    // Deploy mock recipient
    recipient = new OsTokenFlashLoanRecipientMock(_osToken, _osTokenFlashLoans);

    // Mint tokens to the recipient for repayment
    _mintOsToken(address(recipient), 1000 ether);
  }

  function test_flashLoan_success() public {
    // Configure recipient to repay the loan
    recipient.setShouldRepayLoan(true);

    uint256 flashLoanAmount = 100 ether;

    // Record pre-loan state
    uint256 recipientPreBalance = osToken.balanceOf(address(recipient));
    uint256 flashLoansPreBalance = osToken.balanceOf(_osTokenFlashLoans);

    // Execute the flash loan
    vm.expectEmit(true, true, false, false);
    emit IOsTokenFlashLoans.OsTokenFlashLoan(address(recipient), flashLoanAmount);

    vm.prank(address(recipient));
    recipient.executeFlashLoan(flashLoanAmount, '0x');

    // Verify post-loan state
    uint256 recipientPostBalance = osToken.balanceOf(address(recipient));
    uint256 flashLoansPostBalance = osToken.balanceOf(_osTokenFlashLoans);

    // Flash loan contract's balance should be unchanged
    // (It mints tokens, receives repayment, then burns the tokens)
    assertEq(
      flashLoansPostBalance,
      flashLoansPreBalance,
      'Flash loans contract balance should remain the same'
    );

    // Recipient's balance should be reduced by the loan amount
    // (It repays the loan from its own balance)
    assertEq(
      recipientPostBalance,
      recipientPreBalance,
      'Recipient should have the same balance after repaying the loan'
    );
  }

  function test_flashLoan_failure() public {
    // Configure recipient to NOT repay the loan
    recipient.setShouldRepayLoan(false);

    uint256 flashLoanAmount = 100 ether;

    // Execute flash loan - should revert because loan isn't repaid
    vm.prank(address(recipient));
    vm.expectRevert(Errors.FlashLoanFailed.selector);
    recipient.executeFlashLoan(flashLoanAmount, '0x');
  }

  function test_flashLoan_zeroAmount() public {
    // Try to execute flash loan with 0 amount - should revert
    vm.prank(address(recipient));
    vm.expectRevert(Errors.InvalidShares.selector);
    recipient.executeFlashLoan(0, '0x');
  }

  function test_flashLoan_excessiveAmount() public {
    // Try to execute flash loan with more than the max amount - should revert
    uint256 excessiveAmount = MAX_FLASH_LOAN_AMOUNT + 1;

    vm.prank(address(recipient));
    vm.expectRevert(Errors.InvalidShares.selector);
    recipient.executeFlashLoan(excessiveAmount, '0x');
  }

  function test_flashLoan_withUserData() public {
    // Configure recipient to repay the loan
    recipient.setShouldRepayLoan(true);

    uint256 flashLoanAmount = 100 ether;
    bytes memory userData = abi.encode('test data');

    // Execute flash loan with user data
    vm.prank(address(recipient));
    recipient.executeFlashLoan(flashLoanAmount, userData);

    // Test passes if the loan executes without reverting
    // (We can't easily verify the userData was received correctly without modifying the recipient)
  }

  function test_flashLoan_maxAmount() public {
    // Configure recipient to repay the loan
    recipient.setShouldRepayLoan(true);

    // Ensure recipient has enough tokens to repay max loan
    _mintOsToken(address(recipient), MAX_FLASH_LOAN_AMOUNT);

    // Execute flash loan with maximum allowed amount
    vm.prank(address(recipient));
    recipient.executeFlashLoan(MAX_FLASH_LOAN_AMOUNT, '0x');

    // Test passes if the loan executes without reverting
  }

  function test_flashLoan_reentrancy() public {
    // Create a malicious recipient that attempts re-entrancy
    MaliciousRecipient malicious = new MaliciousRecipient(_osToken, _osTokenFlashLoans);

    // Mint tokens to the malicious recipient for repayment
    _mintOsToken(address(recipient), 1000 ether);

    // Attempt the attack - should fail due to nonReentrant modifier
    vm.prank(address(malicious));
    vm.expectRevert(); // Either a custom error or a low-level revert
    malicious.executeAttack(100 ether);
  }

  function test_flashLoan_gasUsage() public {
    // Configure recipient to repay the loan
    recipient.setShouldRepayLoan(true);

    uint256 flashLoanAmount = 100 ether;

    // Measure gas usage
    vm.prank(address(recipient));
    uint256 gasStart = gasleft();
    recipient.executeFlashLoan(flashLoanAmount, '0x');
    uint256 gasUsed = gasStart - gasleft();

    // Optional: assert gas usage is below a reasonable threshold
    assertLt(gasUsed, 300000, 'Flash loan gas usage should be reasonable');
  }
}

// A malicious recipient that attempts to perform a re-entrancy attack
contract MaliciousRecipient is IOsTokenFlashLoanRecipient {
  address public osToken;
  address public flashLoanContract;
  bool public attacking;

  constructor(address _osToken, address _flashLoanContract) {
    osToken = _osToken;
    flashLoanContract = _flashLoanContract;
  }

  function executeAttack(uint256 amount) external {
    OsTokenFlashLoans(flashLoanContract).flashLoan(amount, '0x');
  }

  function receiveFlashLoan(uint256 osTokenShares, bytes calldata) external override {
    require(msg.sender == flashLoanContract, 'Caller is not flash loan contract');

    if (!attacking) {
      attacking = true;

      // Try to call flashLoan again (re-entrancy attempt)
      OsTokenFlashLoans(flashLoanContract).flashLoan(osTokenShares, '0x');

      attacking = false;
    }

    // Repay the original loan
    IERC20(osToken).transfer(msg.sender, osTokenShares);
  }
}
