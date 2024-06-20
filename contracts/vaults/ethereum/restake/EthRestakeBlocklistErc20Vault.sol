// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IEthRestakeBlocklistErc20Vault} from '../../../interfaces/IEthRestakeBlocklistErc20Vault.sol';
import {IEthVaultFactory} from '../../../interfaces/IEthVaultFactory.sol';
import {ERC20Upgradeable} from '../../../base/ERC20Upgradeable.sol';
import {VaultEthStaking, IVaultEthStaking} from '../../modules/VaultEthStaking.sol';
import {VaultVersion, IVaultVersion} from '../../modules/VaultVersion.sol';
import {VaultBlocklist} from '../../modules/VaultBlocklist.sol';
import {EthRestakeErc20Vault, IEthRestakeErc20Vault} from './EthRestakeErc20Vault.sol';

/**
 * @title EthRestakeBlocklistErc20Vault
 * @author StakeWise
 * @notice Defines the native restaking Vault with blocking and ERC-20 functionality on Ethereum
 */
contract EthRestakeBlocklistErc20Vault is
  Initializable,
  EthRestakeErc20Vault,
  VaultBlocklist,
  IEthRestakeBlocklistErc20Vault
{
  using EnumerableSet for EnumerableSet.AddressSet;

  // slither-disable-next-line shadowing-state
  uint8 private constant _version = 3;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param _keeper The address of the Keeper contract
   * @param _vaultsRegistry The address of the VaultsRegistry contract
   * @param _validatorsRegistry The contract address used for registering validators in beacon chain
   * @param sharedMevEscrow The address of the shared MEV escrow
   * @param depositDataRegistry The address of the DepositDataRegistry contract
   * @param eigenPodOwnerImplementation The address of the EigenPodOwner implementation contract
   * @param exitingAssetsClaimDelay The delay after which the assets can be claimed after exiting from staking
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address _keeper,
    address _vaultsRegistry,
    address _validatorsRegistry,
    address sharedMevEscrow,
    address depositDataRegistry,
    address eigenPodOwnerImplementation,
    uint256 exitingAssetsClaimDelay
  )
    EthRestakeErc20Vault(
      _keeper,
      _vaultsRegistry,
      _validatorsRegistry,
      sharedMevEscrow,
      depositDataRegistry,
      eigenPodOwnerImplementation,
      exitingAssetsClaimDelay
    )
  {}

  /// @inheritdoc IEthRestakeErc20Vault
  function initialize(
    bytes calldata params
  )
    external
    payable
    virtual
    override(IEthRestakeErc20Vault, EthRestakeErc20Vault)
    reinitializer(_version)
  {
    // initialize deployed vault
    address _admin = IEthVaultFactory(msg.sender).vaultAdmin();
    __EthRestakeErc20Vault_init(
      _admin,
      IEthVaultFactory(msg.sender).ownMevEscrow(),
      abi.decode(params, (EthRestakeErc20VaultInitParams))
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

  /// @inheritdoc VaultEthStaking
  receive() external payable virtual override {
    if (!_eigenPodOwners.contains(msg.sender)) {
      // if the sender is not an EigenPod owner, deposit the received assets
      _checkBlocklist(msg.sender);
      _deposit(msg.sender, msg.value, address(0));
    }
  }

  /// @inheritdoc IVaultVersion
  function vaultId()
    public
    pure
    virtual
    override(IVaultVersion, EthRestakeErc20Vault)
    returns (bytes32)
  {
    return keccak256('EthRestakeBlocklistErc20Vault');
  }

  /// @inheritdoc IVaultVersion
  function version()
    public
    pure
    virtual
    override(IVaultVersion, EthRestakeErc20Vault)
    returns (uint8)
  {
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
