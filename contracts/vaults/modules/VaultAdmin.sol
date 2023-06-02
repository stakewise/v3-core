// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IVaultAdmin} from '../../interfaces/IVaultAdmin.sol';

/**
 * @title VaultAdmin
 * @author StakeWise
 * @notice Defines the admin functionality for the Vault
 */
abstract contract VaultAdmin is Initializable, IVaultAdmin {
  /// @inheritdoc IVaultAdmin
  address public override admin;

  /// @inheritdoc IVaultAdmin
  function setMetadata(string calldata metadataIpfsHash) external override {
    _checkAdmin();
    emit MetadataUpdated(msg.sender, metadataIpfsHash);
  }

  /**
   * @dev Initializes the VaultAdmin contract
   * @param _admin The address of the Vault admin
   */
  function __VaultAdmin_init(
    address _admin,
    string memory metadataIpfsHash
  ) internal onlyInitializing {
    admin = _admin;
    emit MetadataUpdated(msg.sender, metadataIpfsHash);
  }

  /**
   * @dev Internal method for checking whether the caller is admin
   */
  function _checkAdmin() internal view {
    if (msg.sender != admin) revert AccessDenied();
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
