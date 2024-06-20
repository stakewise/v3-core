// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {ReentrancyGuardUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import {IGnoValidatorsRegistry} from '../../interfaces/IGnoValidatorsRegistry.sol';
import {IKeeperRewards} from '../../interfaces/IKeeperRewards.sol';
import {IXdaiExchange} from '../../interfaces/IXdaiExchange.sol';
import {IVaultGnoStaking} from '../../interfaces/IVaultGnoStaking.sol';
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
  ReentrancyGuardUpgradeable,
  VaultAdmin,
  VaultState,
  VaultValidators,
  VaultEnterExit,
  IVaultGnoStaking
{
  uint256 private constant _securityDeposit = 1e9;

  IERC20 internal immutable _gnoToken;
  address private immutable _xdaiExchange;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   * @param gnoToken The address of the GNO token
   * @param xdaiExchange The address of the xDAI exchange
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(address gnoToken, address xdaiExchange) {
    _gnoToken = IERC20(gnoToken);
    _xdaiExchange = xdaiExchange;
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

  /// @inheritdoc IVaultGnoStaking
  function swapXdaiToGno() external override nonReentrant {
    uint256 balance = address(this).balance;
    // skip swapping for small amounts
    if (balance < 1 gwei) return;

    // swap through xDAI exchange
    uint256 assets = IXdaiExchange(_xdaiExchange).swap{value: balance}();

    // update total assets
    _processTotalAssetsDelta(SafeCast.toInt256(assets));
    emit XdaiSwapped(balance, assets);
  }

  /**
   * @dev Function for receiving xDAI
   */
  receive() external payable {}

  /// @inheritdoc VaultValidators
  function _registerSingleValidator(bytes calldata validator) internal virtual override {
    // pull withdrawals from the deposit contract
    _pullWithdrawals();

    // register single validator
    bytes calldata publicKey = validator[:48];
    uint256 depositAmount = _validatorDeposit();
    _gnoToken.approve(_validatorsRegistry, depositAmount);
    IGnoValidatorsRegistry(_validatorsRegistry).deposit(
      publicKey,
      _withdrawalCredentials(),
      validator[48:144],
      bytes32(validator[144:_validatorLength()]),
      depositAmount
    );

    emit ValidatorRegistered(publicKey);
  }

  /// @inheritdoc VaultValidators
  function _registerMultipleValidators(bytes calldata validators) internal virtual override {
    // pull withdrawals from the deposit contract
    _pullWithdrawals();

    // variables used for batch deposit
    bytes memory publicKeys;
    bytes memory signatures;

    // prepare deposit data
    uint256 startIndex;
    uint256 endIndex;
    bytes calldata validator;
    uint256 validatorLength = _validatorLength();
    uint256 validatorsCount = validators.length / validatorLength;
    bytes32[] memory depositDataRoots = new bytes32[](validatorsCount);
    for (uint256 i = 0; i < validatorsCount; ) {
      endIndex += validatorLength;
      validator = validators[startIndex:endIndex];
      publicKeys = bytes.concat(publicKeys, validator[:48]);
      signatures = bytes.concat(signatures, validator[48:144]);
      depositDataRoots[i] = bytes32(validator[144:validatorLength]);
      startIndex = endIndex;
      emit ValidatorRegistered(validator[:48]);
      startIndex = endIndex;
      unchecked {
        // cannot realistically overflow
        ++i;
      }
    }

    // register validators batch
    _gnoToken.approve(_validatorsRegistry, _validatorDeposit() * validatorsCount);
    IGnoValidatorsRegistry(_validatorsRegistry).batchDeposit(
      publicKeys,
      _withdrawalCredentials(),
      signatures,
      depositDataRoots
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
  function _validatorLength() internal pure virtual override returns (uint256) {
    return 176;
  }

  /// @inheritdoc VaultValidators
  function _validatorDeposit() internal pure virtual override returns (uint256) {
    return 1 ether;
  }

  /**
   * @dev Internal function for calculating Vault withdrawal credentials
   * @return The credentials used for the validators withdrawals
   */
  function _withdrawalCredentials() internal view virtual returns (bytes memory) {
    return abi.encodePacked(bytes1(0x01), bytes11(0x0), address(this));
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
    __ReentrancyGuard_init();

    _deposit(address(this), _securityDeposit, address(0));
    // see https://github.com/OpenZeppelin/openzeppelin-contracts/issues/3706
    SafeERC20.safeTransferFrom(_gnoToken, msg.sender, address(this), _securityDeposit);
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
