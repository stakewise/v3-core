// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.22;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IEthVault} from '../../interfaces/IEthVault.sol';
import {IEthVaultFactory} from '../../interfaces/IEthVaultFactory.sol';
import {Multicall} from '../../base/Multicall.sol';
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

/**
 * @title EthVault
 * @author StakeWise
 * @notice Defines the Ethereum staking Vault
 */
contract EthVault is
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
  VaultEthStaking,
  Multicall,
  IEthVault
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
    uint256 exitingAssetsClaimDelay
  )
    VaultImmutables(_keeper, _vaultsRegistry, _validatorsRegistry)
    VaultEnterExit(exitingAssetsClaimDelay)
    VaultOsToken(osTokenVaultController, osTokenConfig)
    VaultMev(sharedMevEscrow)
  {
    _disableInitializers();
  }

  /// @inheritdoc IEthVault
  function initialize(
    bytes calldata params
  ) external payable virtual override reinitializer(_version) {
    // if admin is already set, it's an upgrade
    if (admin != address(0)) {
      __EthVault_initV2();
      return;
    }
    // initialize deployed vault
    __EthVault_init(
      IEthVaultFactory(msg.sender).vaultAdmin(),
      IEthVaultFactory(msg.sender).ownMevEscrow(),
      abi.decode(params, (EthVaultInitParams))
    );
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

  /// @inheritdoc VaultVersion
  function vaultId() public pure virtual override(IVaultVersion, VaultVersion) returns (bytes32) {
    return keccak256('EthVault');
  }

  /// @inheritdoc IVaultVersion
  function version() public pure virtual override(IVaultVersion, VaultVersion) returns (uint8) {
    return _version;
  }

  /**
   * @dev Initializes the EthVault contract
   * @param admin The address of the admin of the Vault
   * @param ownMevEscrow The address of the MEV escrow owned by the Vault. Zero address if shared MEV escrow is used.
   * @param params The decoded parameters for initializing the EthVault contract
   */
  function __EthVault_init(
    address admin,
    address ownMevEscrow,
    EthVaultInitParams memory params
  ) internal onlyInitializing {
    __VaultAdmin_init(admin, params.metadataIpfsHash);
    // fee recipient is initially set to admin address
    __VaultFee_init(admin, params.feePercent);
    __VaultState_init(params.capacity);
    __VaultValidators_init();
    __VaultMev_init(ownMevEscrow);
    __VaultEthStaking_init();
  }

  /**
   * @dev Initializes the EthVault V2 contract
   */
  function __EthVault_initV2() internal onlyInitializing {
    __VaultState_initV2();
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
