// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {Create2} from '@openzeppelin/contracts/utils/Create2.sol';
import {ERC1967Proxy} from '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import {IEthVaultFactory} from '../../interfaces/IEthVaultFactory.sol';
import {IEthVault} from '../../interfaces/IEthVault.sol';
import {IVaultsRegistry} from '../../interfaces/IVaultsRegistry.sol';
import {VaultMevEscrow} from './mev/VaultMevEscrow.sol';

/**
 * @title EthVaultFactory
 * @author StakeWise
 * @notice Factory for deploying Ethereum staking Vaults
 */
contract EthVaultFactory is IEthVaultFactory {
  /// @inheritdoc IEthVaultFactory
  address public immutable override publicVaultImpl;

  /// @inheritdoc IEthVaultFactory
  mapping(address => uint256) public override nonces;

  bytes32 internal immutable _publicVaultCreateHash;

  IVaultsRegistry internal immutable _vaultsRegistry;

  /**
   * @dev Constructor
   * @param _publicVaultImpl The implementation address of the public Ethereum Vault
   * @param vaultsRegistry The address of the VaultsRegistry
   */
  constructor(address _publicVaultImpl, IVaultsRegistry vaultsRegistry) {
    publicVaultImpl = _publicVaultImpl;
    _vaultsRegistry = vaultsRegistry;
    _publicVaultCreateHash = keccak256(
      abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(_publicVaultImpl, ''))
    );
  }

  /// @inheritdoc IEthVaultFactory
  function createVault(VaultParams calldata params) external override returns (address vault) {
    uint256 nonce = nonces[msg.sender];
    unchecked {
      // cannot realistically overflow
      nonces[msg.sender] = nonce + 1;
    }

    // create vault proxy
    bytes32 salt = keccak256(abi.encode(msg.sender, nonce));
    vault = address(new ERC1967Proxy{salt: salt}(publicVaultImpl, ''));

    // create MEV escrow contract
    address mevEscrow = address(new VaultMevEscrow{salt: salt}(vault));

    // initialize vault
    IEthVault(vault).initialize(
      abi.encode(
        IEthVault.EthVaultInitParams({
          capacity: params.capacity,
          validatorsRoot: params.validatorsRoot,
          admin: msg.sender,
          mevEscrow: mevEscrow,
          feePercent: params.feePercent,
          name: params.name,
          symbol: params.symbol,
          validatorsIpfsHash: params.validatorsIpfsHash,
          metadataIpfsHash: params.metadataIpfsHash
        })
      )
    );

    // add vault to the registry
    _vaultsRegistry.addVault(vault);

    emit VaultCreated(
      msg.sender,
      vault,
      mevEscrow,
      params.capacity,
      params.feePercent,
      params.name,
      params.symbol
    );
  }

  /// @inheritdoc IEthVaultFactory
  function computeAddresses(
    address deployer
  ) public view override returns (address vault, address mevEscrow) {
    bytes32 nonce = keccak256(abi.encode(deployer, nonces[deployer]));
    vault = Create2.computeAddress(nonce, _publicVaultCreateHash);
    mevEscrow = Create2.computeAddress(
      nonce,
      keccak256(abi.encodePacked(type(VaultMevEscrow).creationCode, abi.encode(vault)))
    );
  }
}
