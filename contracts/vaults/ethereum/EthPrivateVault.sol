// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IEthVault} from '../../interfaces/IEthVault.sol';
import {IEthPrivateVault} from '../../interfaces/IEthPrivateVault.sol';
import {IVaultVersion} from '../../interfaces/IVaultVersion.sol';
import {VaultEnterExit} from '../modules/VaultEnterExit.sol';
import {VaultWhitelist} from '../modules/VaultWhitelist.sol';
import {EthVault} from './EthVault.sol';

/**
 * @title EthPrivateVault
 * @author StakeWise
 * @notice Defines the Ethereum staking Vault with whitelist
 */
contract EthPrivateVault is Initializable, EthVault, VaultWhitelist, IEthPrivateVault {
  bytes32 private constant _VAULT_ID = keccak256('EthPrivateVault');

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param _keeper The address of the Keeper contract
   * @param _vaultsRegistry The address of the VaultsRegistry contract
   * @param _validatorsRegistry The contract address used for registering validators in beacon chain
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address _keeper,
    address _vaultsRegistry,
    address _validatorsRegistry
  ) EthVault(_keeper, _vaultsRegistry, _validatorsRegistry) {}

  /// @inheritdoc IEthVault
  function initialize(bytes calldata params) external override(IEthVault, EthVault) initializer {
    EthVaultInitParams memory initParams = abi.decode(params, (EthVaultInitParams));
    __EthVault_init(initParams);
    // whitelister is initially set to admin address
    __VaultWhitelist_init(initParams.admin);
  }

  /// @inheritdoc IVaultVersion
  function vaultId() public pure virtual override(EthVault, IVaultVersion) returns (bytes32) {
    return _VAULT_ID;
  }

  /// @inheritdoc VaultEnterExit
  function _deposit(address to, uint256 assets) internal override returns (uint256 shares) {
    if (!(whitelistedAccounts[msg.sender] && whitelistedAccounts[to])) revert AccessDenied();
    return super._deposit(to, assets);
  }
}
