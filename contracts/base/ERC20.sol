// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.19;

import {IERC20} from '../interfaces/IERC20.sol';
import {IERC20Permit} from '../interfaces/IERC20Permit.sol';

/**
 * @title ERC20
 * @author StakeWise
 * @notice Modern and gas efficient ERC20 + EIP-2612 implementation
 */
abstract contract ERC20 is IERC20Permit {
  bytes32 private constant _permitTypeHash =
    keccak256('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)');

  /// @inheritdoc IERC20
  string public override name;

  /// @inheritdoc IERC20
  string public override symbol;

  /// @inheritdoc IERC20
  uint8 public constant override decimals = 18;

  /// @inheritdoc IERC20
  mapping(address => uint256) public override balanceOf;

  /// @inheritdoc IERC20
  mapping(address => mapping(address => uint256)) public override allowance;

  /// @inheritdoc IERC20Permit
  mapping(address => uint256) public override nonces;

  uint256 private immutable _initialChainId;

  bytes32 private immutable _initialDomainSeparator;

  /**
   * @dev Constructor
   * @param _name The name of the ERC20 token
   * @param _symbol The symbol of the ERC20 token
   */
  constructor(string memory _name, string memory _symbol) {
    name = _name;
    symbol = _symbol;

    _initialChainId = block.chainid;
    _initialDomainSeparator = _computeDomainSeparator();
  }

  /// @inheritdoc IERC20
  function approve(address spender, uint256 amount) public override returns (bool) {
    if (spender == address(0)) revert ZeroAddress();
    allowance[msg.sender][spender] = amount;

    emit Approval(msg.sender, spender, amount);

    return true;
  }

  /// @inheritdoc IERC20Permit
  function increaseAllowance(address spender, uint256 addedValue) external override returns (bool) {
    approve(spender, allowance[msg.sender][spender] + addedValue);
    return true;
  }

  /// @inheritdoc IERC20Permit
  function decreaseAllowance(
    address spender,
    uint256 subtractedValue
  ) external override returns (bool) {
    approve(spender, allowance[msg.sender][spender] - subtractedValue);
    return true;
  }

  /// @inheritdoc IERC20
  function transfer(address to, uint256 amount) public override returns (bool) {
    _transfer(msg.sender, to, amount);
    return true;
  }

  /// @inheritdoc IERC20
  function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
    _spendAllowance(from, msg.sender, amount);
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
    if (spender == address(0)) revert ZeroAddress();
    if (deadline < block.timestamp) revert PermitDeadlineExpired();

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

      if (recoveredAddress == address(0) || recoveredAddress != owner) revert PermitInvalidSigner();

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
  function _transfer(address from, address to, uint256 amount) private {
    if (from == address(0) || to == address(0)) revert ZeroAddress();
    balanceOf[from] -= amount;

    // Cannot overflow because the sum of all user
    // balances can't exceed the max uint256 value
    unchecked {
      balanceOf[to] += amount;
    }

    emit Transfer(from, to, amount);
  }

  /**
   * @dev Updates `owner`s allowance for `spender` based on spent `amount`.
   * Does not update the allowance amount in case of infinite allowance.
   * Revert if not enough allowance is available.
   */
  function _spendAllowance(address owner, address spender, uint256 amount) internal {
    // Saves gas for limited approvals
    uint256 allowed = allowance[owner][spender];

    if (allowed != type(uint256).max) allowance[owner][spender] = allowed - amount;
  }
}
