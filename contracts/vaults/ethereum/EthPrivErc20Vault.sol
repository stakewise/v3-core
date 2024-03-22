// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IEthPrivErc20Vault} from '../../interfaces/IEthPrivErc20Vault.sol';
import {IEthVaultFactory} from '../../interfaces/IEthVaultFactory.sol';
import {ERC20Upgradeable} from '../../base/ERC20Upgradeable.sol';
import {VaultEthStaking, IVaultEthStaking} from '../modules/VaultEthStaking.sol';
import {VaultOsToken, IVaultOsToken} from '../modules/VaultOsToken.sol';
import {VaultWhitelist} from '../modules/VaultWhitelist.sol';
import {VaultVersion, IVaultVersion} from '../modules/VaultVersion.sol';
import {EthErc20Vault, IEthErc20Vault} from './EthErc20Vault.sol';

/**
 * @title EthPrivErc20Vault
 * @author StakeWise
 * @notice Defines the Ethereum staking Vault with whitelist and ERC-20 token
 */
contract EthPrivErc20Vault is Initializable, EthErc20Vault, VaultWhitelist, IEthPrivErc20Vault {
  // slither-disable-next-line shadowing-state
  uint8 private constant _version = 2;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param _keeper The address of the Keeper contract
   * @param _vaultsRegistry The address of the VaultsRegistry contract
   * @param _validatorsRegistry The contract address used for registering validators in beacon chain
   * @param osTokenVaultController The address of the OsTokenVaultController contract
   * @param osTokenConfig The address of the OsTokenConfig contract
   * @param sharedMevEscrow The address of the shared MEV escrow
   * @param depositDataManager The address of the DepositDataManager contract
   * @param exitingAssetsClaimDelay The delay after which the assets can be claimed after exiting from staking
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address _keeper,
    address _vaultsRegistry,
    address _validatorsRegistry,
    address osTokenVaultController,
    address osTokenConfig,
    address sharedMevEscrow,
    address depositDataManager,
    uint256 exitingAssetsClaimDelay
  )
    EthErc20Vault(
      _keeper,
      _vaultsRegistry,
      _validatorsRegistry,
      osTokenVaultController,
      osTokenConfig,
      sharedMevEscrow,
      depositDataManager,
      exitingAssetsClaimDelay
    )
  {}

  /// @inheritdoc IEthErc20Vault
  function initialize(
    bytes calldata params
  ) external payable virtual override(IEthErc20Vault, EthErc20Vault) reinitializer(_version) {
    // if admin is already set, it's an upgrade
    if (admin != address(0)) {
      __EthErc20Vault_initV2();
      return;
    }
    // initialize deployed vault
    address _admin = IEthVaultFactory(msg.sender).vaultAdmin();
    __EthErc20Vault_init(
      _admin,
      IEthVaultFactory(msg.sender).ownMevEscrow(),
      abi.decode(params, (EthErc20VaultInitParams))
    );
    // whitelister is initially set to admin address
    __VaultWhitelist_init(_admin);
  }

  /// @inheritdoc IVaultVersion
  function vaultId() public pure virtual override(IVaultVersion, EthErc20Vault) returns (bytes32) {
    return keccak256('EthPrivErc20Vault');
  }

  /// @inheritdoc IVaultVersion
  function version() public pure virtual override(IVaultVersion, EthErc20Vault) returns (uint8) {
    return _version;
  }

  /// @inheritdoc IVaultEthStaking
  function deposit(
    address receiver,
    address referrer
  ) public payable virtual override(IVaultEthStaking, VaultEthStaking) returns (uint256 shares) {
    _checkWhitelist(msg.sender);
    _checkWhitelist(receiver);
    return super.deposit(receiver, referrer);
  }

  /**
   * @dev Function for depositing using fallback function
   */
  receive() external payable virtual override {
    _checkWhitelist(msg.sender);
    _deposit(msg.sender, msg.value, address(0));
  }

  /// @inheritdoc IVaultOsToken
  function mintOsToken(
    address receiver,
    uint256 osTokenShares,
    address referrer
  ) public virtual override(IVaultOsToken, VaultOsToken) returns (uint256 assets) {
    _checkWhitelist(msg.sender);
    return super.mintOsToken(receiver, osTokenShares, referrer);
  }

  /// @inheritdoc ERC20Upgradeable
  function _transfer(address from, address to, uint256 amount) internal virtual override {
    _checkWhitelist(from);
    _checkWhitelist(to);
    super._transfer(from, to, amount);
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
