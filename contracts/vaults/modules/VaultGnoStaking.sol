// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IGnoValidatorsRegistry} from '../../interfaces/IGnoValidatorsRegistry.sol';
import {IVaultGnoStaking} from '../../interfaces/IVaultGnoStaking.sol';
import {IGnosisDaiDistributor} from '../../interfaces/IGnosisDaiDistributor.sol';
import {Errors} from '../../libraries/Errors.sol';
import {VaultAdmin} from './VaultAdmin.sol';
import {VaultState} from './VaultState.sol';
import {VaultValidators} from './VaultValidators.sol';
import {VaultEnterExit} from './VaultEnterExit.sol';

/**
 * @title VaultGnoStaking
 * @author StakeWise
 * @notice Defines the Gnosis staking functionality for the Vault
 */
abstract contract VaultGnoStaking is
  Initializable,
  VaultAdmin,
  VaultState,
  VaultValidators,
  VaultEnterExit,
  IVaultGnoStaking
{
  uint256 private constant _securityDeposit = 1e9;

  IERC20 internal immutable _gnoToken;
  IGnosisDaiDistributor private immutable _gnosisDaiDistributor;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param gnoToken The address of the GNO token
   * @param gnosisDaiDistributor The address of the xDAI distributor contract
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(address gnoToken, address gnosisDaiDistributor) {
    _gnoToken = IERC20(gnoToken);
    _gnosisDaiDistributor = IGnosisDaiDistributor(gnosisDaiDistributor);
  }

  /// @inheritdoc IVaultGnoStaking
  function deposit(
    uint256 assets,
    address receiver,
    address referrer
  ) public virtual override nonReentrant returns (uint256 shares) {
    // withdraw GNO tokens from the user
    SafeERC20.safeTransferFrom(_gnoToken, msg.sender, address(this), assets);
    shares = _deposit(receiver, assets, referrer);
  }

  /// @inheritdoc VaultState
  function _processTotalAssetsDelta(int256 assetsDelta) internal virtual override {
    super._processTotalAssetsDelta(assetsDelta);

    uint256 balance = address(this).balance;
    if (balance < 0.1 ether) return;

    _gnosisDaiDistributor.distributeDai{value: balance}();
  }

  /**
   * @dev Function for receiving xDAI
   */
  receive() external payable {}

  /// @inheritdoc VaultValidators
  function _registerValidator(
    bytes calldata validator
  ) internal virtual override returns (bytes calldata publicKey, uint256 depositAmount) {
    // pull withdrawals from the deposit contract
    _pullWithdrawals();

    publicKey = validator[:48];
    bytes calldata signature = validator[48:144];
    bytes32 depositDataRoot = bytes32(validator[144:176]);
    bytes1 withdrawalCredsPrefix = bytes1(validator[176:177]);
    // deposit amount was encoded in gwei to save calldata space
    depositAmount = abi.decode(validator[177:185], (uint64)) * 1 gwei;

    // check withdrawal credentials prefix
    if (withdrawalCredsPrefix == bytes1(0x01)) {
      if (depositAmount > _validatorMinEffectiveBalance()) {
        revert Errors.InvalidAssets();
      }
    } else if (withdrawalCredsPrefix == bytes1(0x02)) {
      if (depositAmount > _validatorMaxEffectiveBalance()) {
        revert Errors.InvalidAssets();
      }
    } else {
      revert Errors.InvalidWithdrawalCredentialsPrefix();
    }

    IGnoValidatorsRegistry(_validatorsRegistry).deposit(
      publicKey,
      abi.encodePacked(withdrawalCredsPrefix, bytes11(0x0), address(this)),
      signature,
      depositDataRoot,
      depositAmount
    );
  }

  /// @inheritdoc VaultState
  function _vaultAssets() internal view virtual override returns (uint256) {
    return
      _gnoToken.balanceOf(address(this)) +
      IGnoValidatorsRegistry(_validatorsRegistry).withdrawableAmount(address(this));
  }

  /// @inheritdoc VaultEnterExit
  function _transferVaultAssets(
    address receiver,
    uint256 assets
  ) internal virtual override nonReentrant {
    if (assets > _gnoToken.balanceOf(address(this))) {
      _pullWithdrawals();
    }
    SafeERC20.safeTransfer(_gnoToken, receiver, assets);
  }

  /// @inheritdoc VaultValidators
  function _validatorMinEffectiveBalance() internal pure override returns (uint256) {
    return 1 ether;
  }

  /// @inheritdoc VaultValidators
  function _validatorMaxEffectiveBalance() internal pure override returns (uint256) {
    return 64 ether;
  }

  /**
   * @dev Pulls assets from withdrawal contract
   */
  function _pullWithdrawals() internal virtual {
    IGnoValidatorsRegistry(_validatorsRegistry).claimWithdrawal(address(this));
  }

  /**
   * @dev Initializes the VaultGnoStaking contract
   */
  function __VaultGnoStaking_init() internal onlyInitializing {
    // approve transferring GNO for validators registration
    _gnoToken.approve(_validatorsRegistry, type(uint256).max);

    _deposit(address(this), _securityDeposit, address(0));
    // see https://github.com/OpenZeppelin/openzeppelin-contracts/issues/3706
    SafeERC20.safeTransferFrom(_gnoToken, msg.sender, address(this), _securityDeposit);
  }

  /**
   * @dev Initializes the VaultGnoStaking contract upgrade to V3
   */
  function __VaultGnoStaking_initV3() internal onlyInitializing {
    // approve transferring GNO for validators registration
    _gnoToken.approve(_validatorsRegistry, type(uint256).max);
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
