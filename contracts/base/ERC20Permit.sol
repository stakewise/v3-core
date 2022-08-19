// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import {IERC20} from '../interfaces/IERC20.sol';
import {IERC20Permit} from '../interfaces/IERC20Permit.sol';

/**
 * @title ERC20 Permit Token
 * @author StakeWise
 * @notice Modern and gas efficient ERC20 + EIP-2612 implementation
 * @dev StakeWise added interfaces and docstrings
 */
abstract contract ERC20Permit is IERC20Permit {
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

  uint256 private immutable INITIAL_CHAIN_ID;

  bytes32 private immutable INITIAL_DOMAIN_SEPARATOR;

  error PermitDeadlineExpired();
  error PermitInvalidSigner();

  /**
   * @dev Constructor
   * @param _name The name of the ERC20 token
   * @param _symbol The symbol of the ERC20 token
   */
  constructor(string memory _name, string memory _symbol) {
    // initialize ERC20
    name = _name;
    symbol = _symbol;

    // initialize EIP-2612
    INITIAL_CHAIN_ID = block.chainid;
    INITIAL_DOMAIN_SEPARATOR = _computeDomainSeparator();
  }

  /// @inheritdoc IERC20
  function approve(address spender, uint256 amount) public override returns (bool) {
    allowance[msg.sender][spender] = amount;

    emit Approval(msg.sender, spender, amount);

    return true;
  }

  /// @inheritdoc IERC20
  function transfer(address to, uint256 amount) public override returns (bool) {
    balanceOf[msg.sender] -= amount;

    // Cannot overflow because the sum of all user
    // balances can't exceed the max uint256 value
    unchecked {
      balanceOf[to] += amount;
    }

    emit Transfer(msg.sender, to, amount);

    return true;
  }

  /// @inheritdoc IERC20
  function transferFrom(
    address from,
    address to,
    uint256 amount
  ) public override returns (bool) {
    // Saves gas for limited approvals
    uint256 allowed = allowance[from][msg.sender];

    if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

    balanceOf[from] -= amount;

    // Cannot overflow because the sum of all user
    // balances can't exceed the max uint256 value
    unchecked {
      balanceOf[to] += amount;
    }

    emit Transfer(from, to, amount);

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
    if (deadline < block.timestamp) revert PermitDeadlineExpired();

    // Unchecked because the only math done is incrementing
    // the owner's nonce which cannot realistically overflow
    unchecked {
      address recoveredAddress = ecrecover(
        keccak256(
          abi.encodePacked(
            '\x19\x01',
            DOMAIN_SEPARATOR(),
            keccak256(
              abi.encode(
                keccak256(
                  'Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)'
                ),
                owner,
                spender,
                value,
                nonces[owner]++,
                deadline
              )
            )
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
    return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : _computeDomainSeparator();
  }

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
}
