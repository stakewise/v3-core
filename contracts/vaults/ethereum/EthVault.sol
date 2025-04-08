// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IEthVault} from '../../interfaces/IEthVault.sol';
import {IEthVaultFactory} from '../../interfaces/IEthVaultFactory.sol';
import {IKeeperRewards} from '../../interfaces/IKeeperRewards.sol';
import {Errors} from '../../libraries/Errors.sol';
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
  uint8 private constant _version = 5;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param args The arguments for initializing the EthVault contract
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    EthVaultConstructorArgs memory args
  )
    VaultImmutables(args.keeper, args.vaultsRegistry)
    VaultValidators(
      args.depositDataRegistry,
      args.validatorsRegistry,
      args.validatorsWithdrawals,
      args.validatorsConsolidations,
      args.consolidationsChecker
    )
    VaultEnterExit(args.exitingAssetsClaimDelay)
    VaultOsToken(args.osTokenVaultController, args.osTokenConfig, args.osTokenVaultEscrow)
    VaultMev(args.sharedMevEscrow)
  {
    _disableInitializers();
  }

  /// @inheritdoc IEthVault
  function initialize(
    bytes calldata params
  ) external payable virtual override reinitializer(_version) {
    // if admin is already set, it's an upgrade from version 4 to 5
    if (admin != address(0)) {
      __EthVault_upgrade();
      return;
    }

    // initialize deployed vault
    __EthVault_init(
      IEthVaultFactory(msg.sender).vaultAdmin(),
      IEthVaultFactory(msg.sender).ownMevEscrow(),
      abi.decode(params, (EthVaultInitParams))
    );
  }

  /// @inheritdoc IEthVault
  function depositAndMintOsToken(
    address receiver,
    uint256 osTokenShares,
    address referrer
  ) public payable override returns (uint256) {
    deposit(msg.sender, referrer);
    return mintOsToken(receiver, osTokenShares, referrer);
  }

  /// @inheritdoc IEthVault
  function updateStateAndDepositAndMintOsToken(
    address receiver,
    uint256 osTokenShares,
    address referrer,
    IKeeperRewards.HarvestParams calldata harvestParams
  ) external payable override returns (uint256) {
    updateState(harvestParams);
    return depositAndMintOsToken(receiver, osTokenShares, referrer);
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

  /// @inheritdoc VaultValidators
  function _checkCanWithdrawValidators(
    bytes calldata validators,
    bytes calldata validatorsManagerSignature
  ) internal override {
    if (
      !_isValidatorsManager(
        validators,
        bytes32(validatorsManagerNonce),
        validatorsManagerSignature
      ) && msg.sender != _osTokenConfig.redeemer()
    ) {
      revert Errors.AccessDenied();
    }
  }

  /**
   * @dev Upgrades the EthVault contract
   */
  function __EthVault_upgrade() internal {
    __VaultValidators_upgrade();
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
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
