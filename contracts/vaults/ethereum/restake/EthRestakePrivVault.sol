// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IEthRestakePrivVault} from '../../../interfaces/IEthRestakePrivVault.sol';
import {IEthVaultFactory} from '../../../interfaces/IEthVaultFactory.sol';
import {VaultEthStaking, IVaultEthStaking} from '../../modules/VaultEthStaking.sol';
import {VaultWhitelist} from '../../modules/VaultWhitelist.sol';
import {IVaultVersion} from '../../modules/VaultVersion.sol';
import {EthRestakeVault, IEthRestakeVault} from './EthRestakeVault.sol';

/**
 * @title EthRestakePrivVault
 * @author StakeWise
 * @notice Defines the restaking Vault with whitelist on Ethereum
 */
contract EthRestakePrivVault is
  Initializable,
  EthRestakeVault,
  VaultWhitelist,
  IEthRestakePrivVault
{
  using EnumerableSet for EnumerableSet.AddressSet;

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
    EthRestakeVault(
      _keeper,
      _vaultsRegistry,
      _validatorsRegistry,
      sharedMevEscrow,
      depositDataRegistry,
      eigenPodOwnerImplementation,
      exitingAssetsClaimDelay
    )
  {}

  /// @inheritdoc IEthRestakeVault
  function initialize(
    bytes calldata params
  ) external payable virtual override(IEthRestakeVault, EthRestakeVault) reinitializer(_version) {
    // initialize deployed vault
    address _admin = IEthVaultFactory(msg.sender).vaultAdmin();
    __EthRestakeVault_init(
      _admin,
      IEthVaultFactory(msg.sender).ownMevEscrow(),
      abi.decode(params, (EthRestakeVaultInitParams))
    );
    // whitelister is initially set to admin address
    __VaultWhitelist_init(_admin);
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

  /// @inheritdoc VaultEthStaking
  receive() external payable virtual override {
    if (!_eigenPodOwners.contains(msg.sender)) {
      // if the sender is not an EigenPod owner, deposit the received assets
      _checkWhitelist(msg.sender);
      _deposit(msg.sender, msg.value, address(0));
    }
  }

  /// @inheritdoc IVaultVersion
  function vaultId()
    public
    pure
    virtual
    override(IVaultVersion, EthRestakeVault)
    returns (bytes32)
  {
    return keccak256('EthRestakePrivVault');
  }

  /// @inheritdoc IVaultVersion
  function version() public pure virtual override(IVaultVersion, EthRestakeVault) returns (uint8) {
    return _version;
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
