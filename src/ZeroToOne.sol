// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Zero To One (ZTO)
/// @notice A plain, fixed-supply ERC-20 community token.
/// @dev The whole supply is minted once, to the deployer, in the constructor. There is no owner, no
/// mint or burn function, no fee, no pause, no blocklist and no transfer rule of any kind: after
/// construction the only state changes are holder-initiated transfers and approvals. The contract is
/// self-contained (no inheritance, no external calls, no delegatecall) so what is reviewed here is
/// everything that is deployed.
contract ZeroToOne {
    string public constant name = "Zero To One";
    string public constant symbol = "ZTO";
    uint8 public constant decimals = 18;

    /// @notice 1,000,000,000 ZTO in minor units. Fixed forever: nothing mints or burns after construction.
    uint256 public constant totalSupply = 1_000_000_000 * 10 ** 18;

    mapping(address account => uint256) public balanceOf;
    mapping(address owner => mapping(address spender => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error InsufficientBalance(address from, uint256 balance, uint256 needed);
    error InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error InvalidReceiver(address receiver);
    error InvalidSpender(address spender);

    /// @dev Mints the whole supply to the deployer. In a launch the deployer is the factory.
    constructor() {
        balanceOf[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    /// @notice Moves `value` from the caller to `to`. Exactly `value` arrives; there is no fee.
    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /// @notice Sets the caller's allowance for `spender` to `value`, replacing any previous allowance.
    function approve(address spender, uint256 value) external returns (bool) {
        if (spender == address(0)) revert InvalidSpender(spender);
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /// @notice Moves `value` from `from` to `to` using the caller's allowance.
    /// @dev An allowance of type(uint256).max is treated as unlimited and is not decreased.
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < value) revert InsufficientAllowance(msg.sender, allowed, value);
            unchecked {
                allowance[from][msg.sender] = allowed - value;
            }
        }
        _transfer(from, to, value);
        return true;
    }

    /// @dev The zero address is refused as a receiver so that tokens cannot be sent there by mistake;
    /// since nothing can burn, the sum of balances always equals totalSupply.
    function _transfer(address from, address to, uint256 value) private {
        if (to == address(0)) revert InvalidReceiver(to);
        uint256 fromBalance = balanceOf[from];
        if (fromBalance < value) revert InsufficientBalance(from, fromBalance, value);
        unchecked {
            // fromBalance >= value, and the sum of all balances is totalSupply, so neither line can wrap.
            balanceOf[from] = fromBalance - value;
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
    }
}
