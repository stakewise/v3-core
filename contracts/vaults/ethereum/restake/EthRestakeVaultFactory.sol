// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {ERC1967Proxy} from '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import {Ownable2Step, Ownable} from '@openzeppelin/contracts/access/Ownable2Step.sol';
import {IVaultsRegistry} from '../../../interfaces/IVaultsRegistry.sol';
import {IEthRestakeVaultFactory} from '../../../interfaces/IEthRestakeVaultFactory.sol';
import {IEthRestakeVault} from '../../../interfaces/IEthRestakeVault.sol';
import {Errors} from '../../../libraries/Errors.sol';
import {OwnMevEscrow} from '../mev/OwnMevEscrow.sol';

/**
 * @title EthRestakeVaultFactory
 * @author StakeWise
 * @notice Factory for deploying Ethereum restaking Vaults
 */
contract EthRestakeVaultFactory is Ownable2Step, IEthRestakeVaultFactory {
  IVaultsRegistry internal immutable _vaultsRegistry;

  /// @inheritdoc IEthRestakeVaultFactory
  address public immutable override implementation;

  /// @inheritdoc IEthRestakeVaultFactory
  address public override ownMevEscrow;

  /// @inheritdoc IEthRestakeVaultFactory
  address public override vaultAdmin;

  /**
   * @dev Constructor
   * @param initialOwner The address of the contract owner
   * @param _implementation The implementation address of Vault
   * @param vaultsRegistry The address of the VaultsRegistry contract
   */
  constructor(
    address initialOwner,
    address _implementation,
    IVaultsRegistry vaultsRegistry
  ) Ownable(initialOwner) {
    implementation = _implementation;
    _vaultsRegistry = vaultsRegistry;
  }

  /// @inheritdoc IEthRestakeVaultFactory
  function createVault(
    address admin,
    bytes calldata params,
    bool isOwnMevEscrow
  ) public payable override onlyOwner returns (address vault) {
    if (admin == address(0)) revert Errors.ZeroAddress();

    // create vault
    vault = address(new ERC1967Proxy(implementation, ''));

    // create MEV escrow contract if needed
    address _mevEscrow;
    if (isOwnMevEscrow) {
      _mevEscrow = address(new OwnMevEscrow(vault));
      // set MEV escrow contract so that it can be initialized in the Vault
      ownMevEscrow = _mevEscrow;
    }

    // set admin so that it can be initialized in the Vault
    vaultAdmin = admin;

    // initialize Vault
    IEthRestakeVault(vault).initialize{value: msg.value}(params);

    // cleanup MEV escrow contract
    if (isOwnMevEscrow) delete ownMevEscrow;

    // cleanup admin
    delete vaultAdmin;

    // add vault to the registry
    _vaultsRegistry.addVault(vault);

    // emit event
    emit VaultCreated(admin, vault, _mevEscrow, params);
  }
}
