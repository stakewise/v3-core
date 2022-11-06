// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {IVault} from './IVault.sol';
import {IEthValidatorsRegistry} from './IEthValidatorsRegistry.sol';

/**
 * @title IEthVault
 * @author StakeWise
 * @notice Defines the interface for the EthVault contract
 */
interface IEthVault is IVault {
  /**
   * @notice The ETH Validators Registry
   * @return The address of the ETH validators registry
   */
  function validatorsRegistry() external view returns (IEthValidatorsRegistry);

  /**
   * @dev Initializes the EthVault contract
   * @param initParams The Vault's initialization parameters
   */
  function initialize(IVault.InitParams memory initParams) external;

  /**
   * @notice Deposit assets to the Vault. Must transfer Ether together with the call.
   * @param receiver The address that will receive Vault's shares
   * @return shares The number of shares minted
   */
  function deposit(address receiver) external payable returns (uint256 shares);

  /**
   * @notice Function for registering single validator. Can only be called by the Keeper.
   * @param validator The concatenation of the validator public key, signature and deposit data root
   * @param proof The proof used to verify that the validator is part of the validators Merkle Tree
   */
  function registerValidator(bytes calldata validator, bytes32[] calldata proof) external;

  /**
   * @notice Function for registering multiple validators. Can only be called by the Keeper.
   * @param validators The concatenation of the validators' public key, signature and deposit data root
   * @param proofFlags The multi proof flags for the Merkle Tree verification
   * @param proof The multi proof used for the Merkle Tree verification
   */
  function registerValidators(
    bytes calldata validators,
    bool[] calldata proofFlags,
    bytes32[] calldata proof
  ) external;
}
