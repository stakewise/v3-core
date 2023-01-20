// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {MerkleProof} from '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import {IVaultWhitelist} from '../../interfaces/IVaultWhitelist.sol';
import {VaultAdmin} from './VaultAdmin.sol';

/**
 * @title VaultWhitelist
 * @author StakeWise
 * @notice Defines the whitelisting functionality for the Vault
 */
abstract contract VaultWhitelist is Initializable, VaultAdmin, IVaultWhitelist {
  /// @inheritdoc IVaultWhitelist
  address public override whitelister;

  /// @inheritdoc IVaultWhitelist
  bytes32 public override whitelistRoot;

  /// @inheritdoc IVaultWhitelist
  mapping(address => bool) public override whitelistedAccounts;

  /// @dev Prevents calling a function from anyone except Vault's whitelister
  modifier onlyWhitelister() {
    if (msg.sender != whitelister) revert AccessDenied();
    _;
  }

  /// @inheritdoc IVaultWhitelist
  function updateWhitelist(address account, bool approved) external override onlyWhitelister {
    _updateWhitelist(account, approved);
  }

  /// @inheritdoc IVaultWhitelist
  function joinWhitelist(address account, bytes32[] calldata proof) external {
    // SLOAD to memory
    if (
      !MerkleProof.verifyCalldata(
        proof,
        whitelistRoot,
        keccak256(bytes.concat(keccak256(abi.encode(account))))
      )
    ) {
      revert InvalidWhitelistProof();
    }
    _updateWhitelist(account, true);
  }

  /// @inheritdoc IVaultWhitelist
  function setWhitelistRoot(
    bytes32 _whitelistRoot,
    string calldata whitelistIpfsHash
  ) external override onlyWhitelister {
    whitelistRoot = _whitelistRoot;
    emit WhitelistRootUpdated(msg.sender, _whitelistRoot, whitelistIpfsHash);
  }

  /// @inheritdoc IVaultWhitelist
  function setWhitelister(address _whitelister) external override onlyAdmin {
    _setWhitelister(_whitelister);
  }

  /**
   * @notice Internal function for updating whitelist
   * @param account The address of the account to update
   * @param approved Defines whether account is added to the whitelist or removed
   */
  function _updateWhitelist(address account, bool approved) internal {
    if (whitelistedAccounts[account] == approved) revert WhitelistAlreadyUpdated();
    whitelistedAccounts[account] = approved;
    emit WhitelistUpdated(msg.sender, account, approved);
  }

  /**
   * @dev Internal function for updating the whitelister externally or from the initializer
   * @param _whitelister The address of the new whitelister
   */
  function _setWhitelister(address _whitelister) internal {
    if (_whitelister == address(0)) revert InvalidAccount();

    // update whitelister address
    whitelister = _whitelister;
    emit WhitelisterUpdated(msg.sender, _whitelister);
  }

  /**
   * @dev Initializes the VaultWhitelist contract
   * @param _whitelister The address of the whitelister
   */
  function __VaultWhitelist_init(address _whitelister) internal onlyInitializing {
    _setWhitelister(_whitelister);
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
