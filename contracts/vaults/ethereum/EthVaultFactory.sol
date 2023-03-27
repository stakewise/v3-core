// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {Create2} from '@openzeppelin/contracts/utils/Create2.sol';
import {ERC1967Proxy} from '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import {IEthVaultFactory} from '../../interfaces/IEthVaultFactory.sol';
import {IEthVault} from '../../interfaces/IEthVault.sol';
import {IVaultsRegistry} from '../../interfaces/IVaultsRegistry.sol';
import {OwnMevEscrow} from './mev/OwnMevEscrow.sol';

/**
 * @title EthVaultFactory
 * @author StakeWise
 * @notice Factory for deploying Ethereum staking Vaults
 */
contract EthVaultFactory is IEthVaultFactory {
  /// @inheritdoc IEthVaultFactory
  address public immutable override publicVaultImpl;

  /// @inheritdoc IEthVaultFactory
  address public immutable override privateVaultImpl;

  /// @inheritdoc IEthVaultFactory
  mapping(address => uint256) public override nonces;

  bytes32 internal immutable _publicVaultCreateHash;
  bytes32 internal immutable _privateVaultCreateHash;

  IVaultsRegistry internal immutable _vaultsRegistry;

  /**
   * @dev Constructor
   * @param _publicVaultImpl The implementation address of the public Ethereum Vault
   * @param _privateVaultImpl The implementation address of the private Ethereum Vault
   * @param vaultsRegistry The address of the VaultsRegistry
   */
  constructor(address _publicVaultImpl, address _privateVaultImpl, IVaultsRegistry vaultsRegistry) {
    publicVaultImpl = _publicVaultImpl;
    privateVaultImpl = _privateVaultImpl;
    _vaultsRegistry = vaultsRegistry;

    _publicVaultCreateHash = keccak256(
      abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(_publicVaultImpl, ''))
    );
    _privateVaultCreateHash = keccak256(
      abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(_privateVaultImpl, ''))
    );
  }

  /// @inheritdoc IEthVaultFactory
  function createVault(
    VaultParams calldata params,
    bool isPrivate,
    bool isOwnMevEscrow
  ) external payable override returns (address vault) {
    uint256 nonce = nonces[msg.sender];

    // create vault proxy
    bytes32 salt = keccak256(abi.encode(msg.sender, nonce));

    // slither-disable-start reentrancy-eth
    if (isPrivate) {
      vault = address(new ERC1967Proxy{salt: salt}(privateVaultImpl, ''));
    } else {
      vault = address(new ERC1967Proxy{salt: salt}(publicVaultImpl, ''));
    }
    // slither-disable-end reentrancy-eth

    // create MEV escrow contract
    address mevEscrow;
    if (isOwnMevEscrow) {
      mevEscrow = address(new OwnMevEscrow{salt: salt}(vault));
    }

    // initialize vault
    IEthVault(vault).initialize{value: msg.value}(
      abi.encode(
        IEthVault.EthVaultInitParams({
          capacity: params.capacity,
          validatorsRoot: params.validatorsRoot,
          admin: msg.sender,
          mevEscrow: mevEscrow,
          feePercent: params.feePercent,
          name: params.name,
          symbol: params.symbol,
          metadataIpfsHash: params.metadataIpfsHash
        })
      )
    );

    // add vault to the registry
    _vaultsRegistry.addVault(vault);

    // update nonce
    nonces[msg.sender] = nonce + 1;

    emit VaultCreated(
      msg.sender,
      vault,
      isPrivate,
      mevEscrow,
      params.capacity,
      params.feePercent,
      params.name,
      params.symbol
    );
  }

  /// @inheritdoc IEthVaultFactory
  function computeAddresses(
    address deployer,
    bool isPrivate
  ) public view override returns (address vault, address ownMevEscrow) {
    bytes32 nonce = keccak256(abi.encode(deployer, nonces[deployer]));
    if (isPrivate) {
      vault = Create2.computeAddress(nonce, _privateVaultCreateHash);
    } else {
      vault = Create2.computeAddress(nonce, _publicVaultCreateHash);
    }
    ownMevEscrow = Create2.computeAddress(
      nonce,
      keccak256(abi.encodePacked(type(OwnMevEscrow).creationCode, abi.encode(vault)))
    );
  }
}
