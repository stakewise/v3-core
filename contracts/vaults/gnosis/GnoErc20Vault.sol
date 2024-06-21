// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IGnoErc20Vault} from '../../interfaces/IGnoErc20Vault.sol';
import {IGnoVaultFactory} from '../../interfaces/IGnoVaultFactory.sol';
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
import {VaultGnoStaking} from '../modules/VaultGnoStaking.sol';
import {VaultMev} from '../modules/VaultMev.sol';
import {VaultToken} from '../modules/VaultToken.sol';

/**
 * @title GnoErc20Vault
 * @author StakeWise
 * @notice Defines the Gnosis staking Vault with ERC-20 token
 */
contract GnoErc20Vault is
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
  VaultGnoStaking,
  Multicall,
  IGnoErc20Vault
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
   * @param gnoToken The address of the GNO token
   * @param xdaiExchange The address of the xDAI exchange
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
    address gnoToken,
    address xdaiExchange,
    uint256 exitingAssetsClaimDelay
  )
    VaultImmutables(_keeper, _vaultsRegistry, _validatorsRegistry)
    VaultValidators(depositDataRegistry)
    VaultEnterExit(exitingAssetsClaimDelay)
    VaultOsToken(osTokenVaultController, osTokenConfig)
    VaultMev(sharedMevEscrow)
    VaultGnoStaking(gnoToken, xdaiExchange)
  {
    _disableInitializers();
  }

  /// @inheritdoc IGnoErc20Vault
  function initialize(bytes calldata params) external virtual override reinitializer(_version) {
    // initialize deployed vault
    __GnoErc20Vault_init(
      IGnoVaultFactory(msg.sender).vaultAdmin(),
      IGnoVaultFactory(msg.sender).ownMevEscrow(),
      abi.decode(params, (GnoErc20VaultInitParams))
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
    return keccak256('GnoErc20Vault');
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
   * @dev Initializes the GnoErc20Vault contract
   * @param admin The address of the admin of the Vault
   * @param ownMevEscrow The address of the MEV escrow owned by the Vault. Zero address if shared MEV escrow is used.
   * @param params The decoded parameters for initializing the GnoErc20Vault contract
   */
  function __GnoErc20Vault_init(
    address admin,
    address ownMevEscrow,
    GnoErc20VaultInitParams memory params
  ) internal onlyInitializing {
    __VaultAdmin_init(admin, params.metadataIpfsHash);
    // fee recipient is initially set to admin address
    __VaultFee_init(admin, params.feePercent);
    __VaultState_init(params.capacity);
    __VaultValidators_init();
    __VaultMev_init(ownMevEscrow);
    __VaultToken_init(params.name, params.symbol);
    __VaultGnoStaking_init();
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
