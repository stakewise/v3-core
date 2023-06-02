// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.20;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {IVersioned} from '../../interfaces/IVersioned.sol';
import {IVaultVersion} from '../../interfaces/IVaultVersion.sol';
import {IVaultEnterExit} from '../../interfaces/IVaultEnterExit.sol';
import {IEthVault} from '../../interfaces/IEthVault.sol';
import {IERC20} from '../../interfaces/IERC20.sol';
import {ERC20Upgradeable} from '../../base/ERC20Upgradeable.sol';
import {Multicall} from '../../base/Multicall.sol';
import {VaultValidators} from '../modules/VaultValidators.sol';
import {VaultAdmin} from '../modules/VaultAdmin.sol';
import {VaultFee} from '../modules/VaultFee.sol';
import {VaultVersion} from '../modules/VaultVersion.sol';
import {VaultImmutables} from '../modules/VaultImmutables.sol';
import {VaultToken} from '../modules/VaultToken.sol';
import {VaultState} from '../modules/VaultState.sol';
import {VaultEnterExit} from '../modules/VaultEnterExit.sol';
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
  VaultToken,
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
    VaultImmutables(_keeper, _vaultsRegistry, _validatorsRegistry)
    VaultOsToken(osToken, osTokenConfig)
    VaultMev(sharedMevEscrow)
  {
    _disableInitializers();
  }

  /// @inheritdoc IEthVault
  function initialize(bytes calldata params) external payable virtual override initializer {
    __EthVault_init(abi.decode(params, (EthVaultInitParams)));
  }

  /// @inheritdoc IVaultEnterExit
  function redeem(
    uint256 shares,
    address receiver,
    address owner
  ) public override(IVaultEnterExit, VaultEnterExit, VaultOsToken) returns (uint256 assets) {
    return super.redeem(shares, receiver, owner);
  }

  /// @inheritdoc IVaultEnterExit
  function enterExitQueue(
    uint256 shares,
    address receiver,
    address owner
  )
    public
    override(IVaultEnterExit, VaultEnterExit, VaultOsToken)
    returns (uint256 positionCounter)
  {
    return super.enterExitQueue(shares, receiver, owner);
  }

  /// @inheritdoc IERC20
  function transfer(
    address to,
    uint256 amount
  ) public override(IERC20, ERC20Upgradeable, VaultOsToken) returns (bool) {
    return super.transfer(to, amount);
  }

  /// @inheritdoc IERC20
  function transferFrom(
    address from,
    address to,
    uint256 amount
  ) public override(IERC20, ERC20Upgradeable, VaultOsToken) returns (bool) {
    return super.transferFrom(from, to, amount);
  }

  /**
   * @dev Initializes the EthVault contract
   * @param params The decoded parameters for initializing the EthVault contract
   */
  function __EthVault_init(EthVaultInitParams memory params) internal onlyInitializing {
    __VaultToken_init(params.name, params.symbol, params.capacity);
    __VaultAdmin_init(params.admin, params.metadataIpfsHash);
    // fee recipient is initially set to admin address
    __VaultFee_init(params.admin, params.feePercent);
    __VaultValidators_init();
    __VaultEthStaking_init();
    __VaultMev_init(params.mevEscrow);
  }

  /// @inheritdoc VaultVersion
  function vaultId() public pure virtual override(IVaultVersion, VaultVersion) returns (bytes32) {
    return keccak256('EthVault');
  }

  /// @inheritdoc IVersioned
  function version() public pure virtual override(IVersioned, VaultVersion) returns (uint8) {
    return 1;
  }
}
