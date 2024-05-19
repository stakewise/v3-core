// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.22;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC20Permit} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {Errors} from '../libraries/Errors.sol';

/**
 * @title ERC20 Upgradeable
 * @author StakeWise
 * @notice Modern and gas efficient ERC20 + EIP-2612 implementation
 */
abstract contract ERC20Upgradeable is Initializable, IERC20Permit, IERC20, IERC20Metadata {
  bytes32 private constant _permitTypeHash =
    keccak256('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)');

  /// @inheritdoc IERC20Metadata
  string public override name;

  /// @inheritdoc IERC20Metadata
  string public override symbol;

  /// @inheritdoc IERC20Metadata
  uint8 public constant override decimals = 18;

  /// @inheritdoc IERC20
  mapping(address => mapping(address => uint256)) public override allowance;

  /// @inheritdoc IERC20Permit
  mapping(address => uint256) public override nonces;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  uint256 private immutable _initialChainId;

  bytes32 private _initialDomainSeparator;

  /**
   * @dev Constructor
   * @dev Since the immutable variable value is stored in the bytecode,
   *      its value would be shared among all proxies pointing to a given contract instead of each proxy’s storage.
   */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    // disable initializers for the implementation contract
    _disableInitializers();
    _initialChainId = block.chainid;
  }

  /// @inheritdoc IERC20
  function approve(address spender, uint256 amount) public override returns (bool) {
    if (spender == address(0)) revert Errors.ZeroAddress();
    allowance[msg.sender][spender] = amount;

    emit Approval(msg.sender, spender, amount);

    return true;
  }

  /// @inheritdoc IERC20
  function transfer(address to, uint256 amount) public virtual override returns (bool) {
    _transfer(msg.sender, to, amount);
    return true;
  }

  /// @inheritdoc IERC20
  function transferFrom(
    address from,
    address to,
    uint256 amount
  ) public virtual override returns (bool) {
    // Saves gas for limited approvals
    uint256 allowed = allowance[from][msg.sender];
    if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

    _transfer(from, to, amount);

    return true;
  }

  /// @inheritdoc IERC20Permit
  function permit(
    address owner,
    address spender,
    uint256 value,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) public override {
    if (spender == address(0)) revert Errors.ZeroAddress();
    if (deadline < block.timestamp) revert Errors.DeadlineExpired();

    // Unchecked because the only math done is incrementing
    // the owner's nonce which cannot realistically overflow
    unchecked {
      address recoveredAddress = ecrecover(
        keccak256(
          abi.encodePacked(
            '\x19\x01',
            DOMAIN_SEPARATOR(),
            keccak256(abi.encode(_permitTypeHash, owner, spender, value, nonces[owner]++, deadline))
          )
        ),
        v,
        r,
        s
      );

      if (recoveredAddress == address(0) || recoveredAddress != owner)
        revert Errors.PermitInvalidSigner();

      allowance[recoveredAddress][spender] = value;
    }

    emit Approval(owner, spender, value);
  }

  /// @inheritdoc IERC20Permit
  function DOMAIN_SEPARATOR() public view override returns (bytes32) {
    return block.chainid == _initialChainId ? _initialDomainSeparator : _computeDomainSeparator();
  }

  /**
   * @notice Computes the hash of the EIP712 typed data
   * @dev This function is used to compute the hash of the EIP712 typed data
   */
  function _computeDomainSeparator() private view returns (bytes32) {
    return
      keccak256(
        abi.encode(
          keccak256(
            'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
          ),
          keccak256(bytes(name)),
          keccak256('1'),
          block.chainid,
          address(this)
        )
      );
  }

  /**
   * @dev Moves `amount` of tokens from `from` to `to`.
   * Emits a {Transfer} event.
   */
  function _transfer(address from, address to, uint256 amount) internal virtual;

  /**
   * @dev Initializes the ERC20Upgradeable contract
   * @param _name The name of the ERC20 token
   * @param _symbol The symbol of the ERC20 token
   */
  function __ERC20Upgradeable_init(
    string memory _name,
    string memory _symbol
  ) internal onlyInitializing {
    // initialize ERC20
    name = _name;
    symbol = _symbol;

    // initialize EIP-2612
    _initialDomainSeparator = _computeDomainSeparator();
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;
}
