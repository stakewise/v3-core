// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.16;

import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {EthVault} from '../vaults/EthVault.sol';

/**
 * @title EthVaultMock
 * @author StakeWise
 * @notice Adds mocked functions to the EthVault contract
 */
contract EthVaultMock is EthVault {
  using SafeCast for uint256;

  /**
   * @dev Constructor
   * @param vaultId The ID of the Vault
   */
  constructor(uint256 vaultId) EthVault(vaultId) {}

  function mockMint(address receiver, uint256 assets) external returns (uint256 shares) {
    // calculate amount of shares to mint
    shares = convertToShares(assets);

    // update counters
    _totalShares += SafeCast.toUint128(shares);

    unchecked {
      // Cannot overflow because the sum of all user
      // balances can't exceed the max uint256 value
      balanceOf[receiver] += shares;
    }

    emit Transfer(address(0), receiver, shares);
    emit Deposit(msg.sender, receiver, assets, shares);
  }

  function _setTotalStakedAssets(uint128 value) external {
    _totalStakedAssets = value;
  }
}
