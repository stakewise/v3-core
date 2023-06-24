// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IEthVault} from '../../interfaces/IEthVault.sol';
import {IEthPrivVault} from '../../interfaces/IEthPrivVault.sol';
import {IEthVaultFactory} from '../../interfaces/IEthVaultFactory.sol';
import {IVaultEthStaking} from '../../interfaces/IVaultEthStaking.sol';
import {IVaultVersion} from '../../interfaces/IVaultVersion.sol';
import {Errors} from '../../libraries/Errors.sol';
import {VaultEthStaking} from '../modules/VaultEthStaking.sol';
import {VaultWhitelist} from '../modules/VaultWhitelist.sol';
import {VaultVersion} from '../modules/VaultVersion.sol';
import {EthVault} from './EthVault.sol';

/**
 * @title EthPrivVault
 * @author StakeWise
 * @notice Defines the Ethereum staking Vault with whitelist
 */
contract EthPrivVault is Initializable, EthVault, VaultWhitelist, IEthPrivVault {
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
  ) external payable virtual override(IEthVault, EthVault) initializer {
    address admin = IEthVaultFactory(msg.sender).vaultAdmin();
    __EthVault_init(
      admin,
      IEthVaultFactory(msg.sender).ownMevEscrow(),
      abi.decode(params, (EthVaultInitParams))
    );
    // whitelister is initially set to admin address
    __VaultWhitelist_init(admin);
  }

  /// @inheritdoc IVaultEthStaking
  function deposit(
    address receiver,
    address referrer
  ) public payable virtual override(IVaultEthStaking, VaultEthStaking) returns (uint256 shares) {
    if (!(whitelistedAccounts[msg.sender] && whitelistedAccounts[receiver])) {
      revert Errors.AccessDenied();
    }
    return super.deposit(receiver, referrer);
  }

  /**
   * @dev Function for depositing using fallback function
   */
  receive() external payable virtual override {
    if (!whitelistedAccounts[msg.sender]) revert Errors.AccessDenied();
    _deposit(msg.sender, msg.value, address(0));
  }

  /// @inheritdoc IVaultVersion
  function vaultId() public pure virtual override(IVaultVersion, EthVault) returns (bytes32) {
    return keccak256('EthPrivVault');
  }

  /// @inheritdoc IVaultVersion
  function version() public pure virtual override(IVaultVersion, EthVault) returns (uint8) {
    return 1;
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
