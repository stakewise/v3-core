// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {IERC20Permit} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol';

/**
 * @title IOsToken
 * @author StakeWise
 * @notice Defines the interface for the OsToken contract
 */
interface IOsToken is IERC20Permit {
  /**
   * @notice Emitted when a controller is updated
   * @param controller The address of the controller
   * @param registered Whether the controller is registered or not
   */
  event ControllerUpdated(address indexed controller, bool registered);

  /**
   * @notice Returns whether controller is registered or not
   * @param controller The address of the controller
   * @return Whether the controller is registered or not
   */
  function controllers(address controller) external view returns (bool);

  /**
   * @notice Mint OsToken. Can only be called by the controller.
   * @param account The address of the account to mint OsToken for
   * @param value The amount of OsToken to mint
   */
  function mint(address account, uint256 value) external;

  /**
   * @notice Burn OsToken. Can only be called by the controller.
   * @param account The address of the account to burn OsToken for
   * @param value The amount of OsToken to burn
   */
  function burn(address account, uint256 value) external;

  /**
   * @notice Enable or disable the controller. Can only be called by the contract owner.
   * @param controller The address of the controller
   * @param registered Whether the controller is registered or not
   */
  function setController(address controller, bool registered) external;
}
