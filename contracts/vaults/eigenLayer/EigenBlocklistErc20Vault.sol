// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IEigenBlocklistErc20Vault} from '../../interfaces/IEigenBlocklistErc20Vault.sol';
import {IEthVaultFactory} from '../../interfaces/IEthVaultFactory.sol';
import {ERC20Upgradeable} from '../../base/ERC20Upgradeable.sol';
import {VaultEthStaking, IVaultEthStaking} from '../modules/VaultEthStaking.sol';
import {VaultVersion, IVaultVersion} from '../modules/VaultVersion.sol';
import {VaultBlocklist} from '../modules/VaultBlocklist.sol';
import {EigenErc20Vault, IEigenErc20Vault} from './EigenErc20Vault.sol';

/**
 * @title EigenBlocklistErc20Vault
 * @author StakeWise
 * @notice Defines the EigenLayer staking Vault with blocking and ERC-20 functionality
 */
contract EigenBlocklistErc20Vault is
  Initializable,
  EigenErc20Vault,
  VaultBlocklist,
  IEigenBlocklistErc20Vault
{
  // slither-disable-next-line shadowing-state
  uint8 private constant _version = 2;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param _keeper The address of the Keeper contract
   * @param _vaultsRegistry The address of the VaultsRegistry contract
   * @param _validatorsRegistry The contract address used for registering validators in beacon chain
   * @param sharedMevEscrow The address of the shared MEV escrow
   * @param depositDataManager The address of the DepositDataManager contract
   * @param eigenDelegationManager The address of the EigenDelegationManager contract
   * @param eigenDelayedWithdrawalRouter The address of the EigenDelayedWithdrawalRouter contract
   * @param eigenPodProxyFactory The address of the EigenPodProxyFactory contract
   * @param exitingAssetsClaimDelay The delay after which the assets can be claimed after exiting from staking
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address _keeper,
    address _vaultsRegistry,
    address _validatorsRegistry,
    address sharedMevEscrow,
    address depositDataManager,
    address eigenPodManager,
    address eigenDelegationManager,
    address eigenDelayedWithdrawalRouter,
    address eigenPodProxyFactory,
    uint256 exitingAssetsClaimDelay
  )
    EigenErc20Vault(
      _keeper,
      _vaultsRegistry,
      _validatorsRegistry,
      sharedMevEscrow,
      depositDataManager,
      eigenPodManager,
      eigenDelegationManager,
      eigenDelayedWithdrawalRouter,
      eigenPodProxyFactory,
      exitingAssetsClaimDelay
    )
  {}

  /// @inheritdoc IEigenErc20Vault
  function initialize(
    bytes calldata params
  ) external payable virtual override(IEigenErc20Vault, EigenErc20Vault) reinitializer(_version) {
    // initialize deployed vault
    address _admin = IEthVaultFactory(msg.sender).vaultAdmin();
    __EigenErc20Vault_init(
      _admin,
      IEthVaultFactory(msg.sender).ownMevEscrow(),
      abi.decode(params, (EigenErc20VaultInitParams))
    );
    // blocklist manager is initially set to admin address
    __VaultBlocklist_init(_admin);
  }

  /// @inheritdoc IVaultEthStaking
  function deposit(
    address receiver,
    address referrer
  ) public payable virtual override(IVaultEthStaking, VaultEthStaking) returns (uint256 shares) {
    _checkBlocklist(msg.sender);
    _checkBlocklist(receiver);
    return super.deposit(receiver, referrer);
  }

  /**
   * @dev Function for depositing using fallback function
   */
  receive() external payable virtual override {
    _checkBlocklist(msg.sender);
    _deposit(msg.sender, msg.value, address(0));
  }

  /// @inheritdoc IVaultVersion
  function vaultId()
    public
    pure
    virtual
    override(IVaultVersion, EigenErc20Vault)
    returns (bytes32)
  {
    return keccak256('EigenBlocklistErc20Vault');
  }

  /// @inheritdoc IVaultVersion
  function version() public pure virtual override(IVaultVersion, EigenErc20Vault) returns (uint8) {
    return _version;
  }

  /// @inheritdoc ERC20Upgradeable
  function _transfer(address from, address to, uint256 amount) internal virtual override {
    _checkBlocklist(from);
    _checkBlocklist(to);
    super._transfer(from, to, amount);
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
