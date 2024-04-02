// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IEthErc20Vault} from '../../interfaces/IEthErc20Vault.sol';
import {IEthVaultFactory} from '../../interfaces/IEthVaultFactory.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Multicall} from '../../base/Multicall.sol';
import {ERC20Upgradeable} from '../../base/ERC20Upgradeable.sol';
import {VaultValidators} from '../modules/VaultValidators.sol';
import {VaultAdmin} from '../modules/VaultAdmin.sol';
import {VaultFee} from '../modules/VaultFee.sol';
import {VaultVersion, IVaultVersion} from '../modules/VaultVersion.sol';
import {VaultImmutables} from '../modules/VaultImmutables.sol';
import {VaultState} from '../modules/VaultState.sol';
import {VaultEnterExit, IVaultEnterExit} from '../modules/VaultEnterExit.sol';
import {VaultOsToken} from '../modules/VaultOsToken.sol';
import {VaultEthStaking} from '../modules/VaultEthStaking.sol';
import {VaultMev} from '../modules/VaultMev.sol';
import {VaultToken} from '../modules/VaultToken.sol';

/**
 * @title EthErc20Vault
 * @author StakeWise
 * @notice Defines the Ethereum staking Vault with ERC-20 token
 */
contract EthErc20Vault is
  VaultImmutables,
  Initializable,
  VaultAdmin,
  VaultVersion,
  VaultFee,
  VaultState,
  VaultValidators,
  VaultEnterExit,
  VaultOsToken,
  VaultMev,
  VaultToken,
  VaultEthStaking,
  Multicall,
  IEthErc20Vault
{
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
   * @param depositDataRegistry The address of the DepositDataRegistry contract
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
    address depositDataRegistry,
    uint256 exitingAssetsClaimDelay
  )
    VaultImmutables(_keeper, _vaultsRegistry, _validatorsRegistry)
    VaultValidators(depositDataRegistry)
    VaultEnterExit(exitingAssetsClaimDelay)
    VaultOsToken(osTokenVaultController, osTokenConfig)
    VaultMev(sharedMevEscrow)
  {
    _disableInitializers();
  }

  /// @inheritdoc IEthErc20Vault
  function initialize(
    bytes calldata params
  ) external payable virtual override reinitializer(_version) {
    // if admin is already set, it's an upgrade
    if (admin != address(0)) {
      __EthErc20Vault_initV2();
      return;
    }
    // initialize deployed vault
    __EthErc20Vault_init(
      IEthVaultFactory(msg.sender).vaultAdmin(),
      IEthVaultFactory(msg.sender).ownMevEscrow(),
      abi.decode(params, (EthErc20VaultInitParams))
    );
  }

  /// @inheritdoc IERC20
  function transfer(
    address to,
    uint256 amount
  ) public virtual override(IERC20, ERC20Upgradeable) returns (bool) {
    bool success = super.transfer(to, amount);
    _checkOsTokenPosition(msg.sender);
    return success;
  }

  /// @inheritdoc IERC20
  function transferFrom(
    address from,
    address to,
    uint256 amount
  ) public virtual override(IERC20, ERC20Upgradeable) returns (bool) {
    bool success = super.transferFrom(from, to, amount);
    _checkOsTokenPosition(from);
    return success;
  }

  /// @inheritdoc IVaultEnterExit
  function enterExitQueue(
    uint256 shares,
    address receiver
  )
    public
    virtual
    override(IVaultEnterExit, VaultEnterExit, VaultOsToken)
    returns (uint256 positionTicket)
  {
    return super.enterExitQueue(shares, receiver);
  }

  /// @inheritdoc IVaultVersion
  function vaultId() public pure virtual override(IVaultVersion, VaultVersion) returns (bytes32) {
    return keccak256('EthErc20Vault');
  }

  /// @inheritdoc IVaultVersion
  function version() public pure virtual override(IVaultVersion, VaultVersion) returns (uint8) {
    return _version;
  }

  /// @inheritdoc VaultState
  function _updateExitQueue()
    internal
    virtual
    override(VaultState, VaultToken)
    returns (uint256 burnedShares)
  {
    return super._updateExitQueue();
  }

  /// @inheritdoc VaultState
  function _mintShares(
    address owner,
    uint256 shares
  ) internal virtual override(VaultState, VaultToken) {
    super._mintShares(owner, shares);
  }

  /// @inheritdoc VaultState
  function _burnShares(
    address owner,
    uint256 shares
  ) internal virtual override(VaultState, VaultToken) {
    super._burnShares(owner, shares);
  }

  /**
   * @dev Initializes the EthErc20Vault contract
   * @param admin The address of the admin of the Vault
   * @param ownMevEscrow The address of the MEV escrow owned by the Vault. Zero address if shared MEV escrow is used.
   * @param params The decoded parameters for initializing the EthErc20Vault contract
   */
  function __EthErc20Vault_init(
    address admin,
    address ownMevEscrow,
    EthErc20VaultInitParams memory params
  ) internal onlyInitializing {
    __VaultAdmin_init(admin, params.metadataIpfsHash);
    // fee recipient is initially set to admin address
    __VaultFee_init(admin, params.feePercent);
    __VaultState_init(params.capacity);
    __VaultValidators_init();
    __VaultMev_init(ownMevEscrow);
    __VaultToken_init(params.name, params.symbol);
    __VaultEthStaking_init();
  }

  /**
   * @dev Initializes the EthErc20Vault V2 contract
   */
  function __EthErc20Vault_initV2() internal onlyInitializing {
    __VaultState_initV2();
    __VaultValidators_initV2();
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
