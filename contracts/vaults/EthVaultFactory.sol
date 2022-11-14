// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

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
    uint256 maxTotalAssets,
    bytes32 validatorsRoot,
    uint16 feePercent,
    string calldata name,
    string calldata symbol,
    string calldata validatorsIpfsHash
  ) external override returns (address vault, address feesEscrow) {
    bytes32 operatorNonce = keccak256(abi.encode(msg.sender, nonces[msg.sender]));

    // create vault proxy
    vault = address(new ERC1967Proxy{salt: operatorNonce}(vaultImplementation, ''));

    // create fees escrow contract
    feesEscrow = address(new EthFeesEscrow{salt: operatorNonce}(vault));

    // initialize vault
    IEthVault(vault).initialize(
      IBaseVault.InitParams({
        maxTotalAssets: maxTotalAssets,
        validatorsRoot: validatorsRoot,
        operator: msg.sender,
        feesEscrow: feesEscrow,
        feePercent: feePercent,
        name: name,
        symbol: symbol,
        validatorsIpfsHash: validatorsIpfsHash
      })
    );

    unchecked {
      // cannot realistically overflow
      nonces[msg.sender] += 1;
    }

    // add vault to the registry
    registry.addVault(vault);

    emit VaultCreated(
      msg.sender,
      vault,
      feesEscrow,
      maxTotalAssets,
      validatorsRoot,
      feePercent,
      name,
      symbol,
      validatorsIpfsHash
    );
  }

  /// @inheritdoc IEthVaultFactory
  function computeAddresses(
    address operator
  ) external view override returns (address vault, address feesEscrow) {
    bytes32 operatorNonce = keccak256(abi.encode(operator, nonces[operator]));
    vault = address(
      uint160(
        uint256(
          keccak256(
            abi.encodePacked(
              bytes1(0xFF), // prefix
              address(this), // creator
              operatorNonce, // salt
              _vaultCreationCodeHash // vault bytecode hash
            )
          )
        )
      )
    );
    feesEscrow = address(
      uint160(
        uint256(
          keccak256(
            abi.encodePacked(
              bytes1(0xFF), // prefix
              address(this), // creator
              operatorNonce, // salt
              keccak256(abi.encodePacked(type(EthFeesEscrow).creationCode, abi.encode(vault))) // escrow bytecode hash
            )
          )
        )
      )
    );
  }
}
