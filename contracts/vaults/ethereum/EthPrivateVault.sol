// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IEthVault} from '../../interfaces/IEthVault.sol';
import {IEthPrivateVault} from '../../interfaces/IEthPrivateVault.sol';
import {IVaultEthStaking} from '../../interfaces/IVaultEthStaking.sol';
import {IVersioned} from '../../interfaces/IVersioned.sol';
import {IVaultVersion} from '../../interfaces/IVaultVersion.sol';
import {VaultEthStaking} from '../modules/VaultEthStaking.sol';
import {VaultWhitelist} from '../modules/VaultWhitelist.sol';
import {EthVault} from './EthVault.sol';

/**
 * @title EthPrivateVault
 * @author StakeWise
 * @notice Defines the Ethereum staking Vault with whitelist
 */
contract EthPrivateVault is Initializable, EthVault, VaultWhitelist, IEthPrivateVault {
  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param _keeper The address of the Keeper contract
   * @param _vaultsRegistry The address of the VaultsRegistry contract
   * @param _validatorsRegistry The contract address used for registering validators in beacon chain
   * @param osToken The address of the OsToken contract
   * @param osTokenConfig The address of the OsTokenConfig contract
   * @param sharedMevEscrow The address of the shared MEV escrow
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address _keeper,
    address _vaultsRegistry,
    address _validatorsRegistry,
    address osToken,
    address osTokenConfig,
    address sharedMevEscrow
  )
    EthVault(_keeper, _vaultsRegistry, _validatorsRegistry, osToken, osTokenConfig, sharedMevEscrow)
  {}

  /// @inheritdoc IEthVault
  function initialize(
    bytes calldata params
  ) external payable override(IEthVault, EthVault) initializer {
    EthVaultInitParams memory initParams = abi.decode(params, (EthVaultInitParams));
    __EthVault_init(initParams);
    // whitelister is initially set to admin address
    __VaultWhitelist_init(initParams.admin);
  }

  /// @inheritdoc IVaultVersion
  function vaultId() public pure virtual override(EthVault, IVaultVersion) returns (bytes32) {
    return keccak256('EthPrivateVault');
  }

  /// @inheritdoc IVersioned
  function version() public pure virtual override(EthVault, IVersioned) returns (uint8) {
    return 1;
  }

  /// @inheritdoc IVaultEthStaking
  function deposit(
    address receiver,
    address referrer
  ) public payable override(IVaultEthStaking, VaultEthStaking) returns (uint256 shares) {
    if (!(whitelistedAccounts[msg.sender] && whitelistedAccounts[receiver])) revert AccessDenied();
    return super.deposit(receiver, referrer);
  }

  /**
   * @dev Function for depositing using fallback function
   */
  receive() external payable override {
    if (!whitelistedAccounts[msg.sender]) revert AccessDenied();
    _deposit(msg.sender, msg.value, address(0));
  }
}
