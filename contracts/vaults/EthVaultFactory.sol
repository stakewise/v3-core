// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {Create2} from '@openzeppelin/contracts/utils/Create2.sol';
import {ERC1967Proxy} from '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import {IEthVaultFactory} from '../interfaces/IEthVaultFactory.sol';
import {IRegistry} from '../interfaces/IRegistry.sol';
import {IEthVault} from '../interfaces/IEthVault.sol';
import {IBaseVault} from '../interfaces/IBaseVault.sol';
import {EthFeesEscrow} from './EthFeesEscrow.sol';

/**
 * @title EthVaultFactory
 * @author StakeWise
 * @notice Factory for deploying Ethereum staking Vaults
 */
contract EthVaultFactory is IEthVaultFactory {
  /// @inheritdoc IEthVaultFactory
  address public immutable override vaultImplementation;

  /// @inheritdoc IEthVaultFactory
  IRegistry public immutable override registry;

  /// @inheritdoc IEthVaultFactory
  mapping(address => uint256) public override nonces;

  bytes32 internal immutable _vaultCreationCodeHash;

  /**
   * @dev Constructor
   * @param _vaultImplementation The address of the Vault implementation used for the proxy deployment
   * @param _registry The address of the Registry
   */
  constructor(address _vaultImplementation, IRegistry _registry) {
    vaultImplementation = _vaultImplementation;
    registry = _registry;
    _vaultCreationCodeHash = keccak256(
      abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(_vaultImplementation, ''))
    );
  }

  /// @inheritdoc IEthVaultFactory
  function createVault(
    VaultParams calldata params
  ) external override returns (address vault, address feesEscrow) {
    uint256 nonce = nonces[msg.sender];
    unchecked {
      // cannot realistically overflow
      nonces[msg.sender] = nonce + 1;
    }

    // create vault proxy
    bytes32 salt = keccak256(abi.encode(msg.sender, nonce));
    vault = address(new ERC1967Proxy{salt: salt}(vaultImplementation, ''));

    // create fees escrow contract
    feesEscrow = address(new EthFeesEscrow{salt: salt}(vault));

    // initialize vault
    IEthVault(vault).initialize(
      IBaseVault.InitParams({
        capacity: params.capacity,
        validatorsRoot: params.validatorsRoot,
        admin: msg.sender,
        feesEscrow: feesEscrow,
        feePercent: params.feePercent,
        name: params.name,
        symbol: params.symbol,
        validatorsIpfsHash: params.validatorsIpfsHash,
        metadataIpfsHash: params.metadataIpfsHash
      })
    );

    // add vault to the registry
    registry.addVault(vault);

    emit VaultCreated(msg.sender, vault, feesEscrow, params);
  }

  /// @inheritdoc IEthVaultFactory
  function computeAddresses(
    address deployer
  ) public view override returns (address vault, address feesEscrow) {
    bytes32 nonce = keccak256(abi.encode(deployer, nonces[deployer]));
    vault = Create2.computeAddress(nonce, _vaultCreationCodeHash);
    feesEscrow = Create2.computeAddress(
      nonce,
      keccak256(abi.encodePacked(type(EthFeesEscrow).creationCode, abi.encode(vault)))
    );
  }
}
