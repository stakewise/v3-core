// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {IKeeperValidators} from './IKeeperValidators.sol';
import {IVaultAdmin} from './IVaultAdmin.sol';
import {IVaultState} from './IVaultState.sol';

/**
 * @title IVaultValidators
 * @author StakeWise
 * @notice Defines the interface for VaultValidators contract
 */
interface IVaultValidators is IVaultAdmin, IVaultState {
  /**
   * @notice Event emitted on validator registration
   * @param publicKey The public key of the validator that was registered
   */
  event ValidatorRegistered(bytes publicKey);

  /**
   * @notice Event emitted on keys manager address update (deprecated)
   * @param caller The address of the function caller
   * @param keysManager The address of the new keys manager
   */
  event KeysManagerUpdated(address indexed caller, address indexed keysManager);

  /**
   * @notice Event emitted on validators merkle tree root update (deprecated)
   * @param caller The address of the function caller
   * @param validatorsRoot The new validators merkle tree root
   */
  event ValidatorsRootUpdated(address indexed caller, bytes32 indexed validatorsRoot);

  /**
   * @notice Event emitted on validators manager address update
   * @param caller The address of the function caller
   * @param validatorsManager The address of the new validators manager
   */
  event ValidatorsManagerUpdated(address indexed caller, address indexed validatorsManager);

  /**
   * @notice The Vault validators manager address
   * @return The address that can register validators
   */
  function validatorsManager() external view returns (address);

  /**
   * @notice Function for registering single or multiple validators
   * @param keeperParams The parameters for getting approval from Keeper oracles
   * @param validatorsManagerSignature The optional signature from the validators manager
   */
  function registerValidators(
    IKeeperValidators.ApprovalParams calldata keeperParams,
    bytes calldata validatorsManagerSignature
  ) external;

  /**
   * @notice Function for updating the validators manager. Can only be called by the admin. Default is the DepositDataRegistry contract.
   * @param _validatorsManager The new validators manager address
   */
  function setValidatorsManager(address _validatorsManager) external;
}
