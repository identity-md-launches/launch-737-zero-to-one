// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ZeroToOne} from "../src/ZeroToOne.sol";

/// @dev Moves tokens among a fixed set of actors through every state-changing entry point.
contract ZeroToOneHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    ZeroToOne public immutable token;
    address[] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(ZeroToOne token_, address[] memory actors_) {
        token = token_;
        actors = actors_;
        // Seed the model from the requested supply, never from token getters.
        expectedBalance[actors_[0]] = SUPPLY;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        _transfer(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        _approve(actors[ownerSeed % actors.length], actors[spenderSeed % actors.length], bound(amount, 0, SUPPLY));
    }

    function approveUnlimited(uint256 ownerSeed, uint256 spenderSeed) external {
        _approve(actors[ownerSeed % actors.length], actors[spenderSeed % actors.length], type(uint256).max);
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        _approve(actors[ownerSeed % actors.length], actors[spenderSeed % actors.length], 0);
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 limit = expectedBalance[from];
        uint256 allowed = expectedAllowance[from][spender];
        if (allowed < limit) limit = allowed;
        amount = bound(amount, 0, limit);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        if (allowed != type(uint256).max) expectedAllowance[from][spender] = allowed - amount;
        _recordTransfer(from, to, amount);
    }

    function transferFullBalance(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        _transfer(from, actors[toSeed % actors.length], expectedBalance[from]);
    }

    function selfTransfer(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        _transfer(owner, owner, bound(amount, 0, expectedBalance[owner]));
    }

    /// @dev Exercise failure after allowance deduction as well as direct overspending.
    function rejectOverspend(uint256 fromSeed, uint256 spenderSeed, uint256 extra) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 held = expectedBalance[from];
        uint256 amount = bound(extra, held + 1, type(uint256).max - 1);
        _approve(from, spender, amount);
        bytes memory errorData = abi.encodeWithSelector(ZeroToOne.InsufficientBalance.selector, from, held, amount);

        vm.expectRevert(errorData);
        vm.prank(from);
        token.transfer(spender, amount);
        vm.expectRevert(errorData);
        vm.prank(spender);
        token.transferFrom(from, spender, amount);
        // The global allowance model is unchanged: the failed debit must be rolled back.
    }

    function rejectUnauthorized(uint256 fromSeed, uint256 spenderSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(from, spender, 0);
        amount = bound(amount, 1, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(ZeroToOne.InsufficientAllowance.selector, spender, 0, amount));
        vm.prank(spender);
        token.transferFrom(from, spender, amount);
    }

    function rejectZeroReceiver(uint256 fromSeed, uint256 spenderSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        _approve(from, spender, amount);
        bytes memory errorData = abi.encodeWithSelector(ZeroToOne.InvalidReceiver.selector, address(0));
        vm.expectRevert(errorData);
        vm.prank(from);
        token.transfer(address(0), amount);
        vm.expectRevert(errorData);
        vm.prank(spender);
        token.transferFrom(from, address(0), amount);
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        vm.expectRevert(abi.encodeWithSelector(ZeroToOne.InvalidSpender.selector, address(0)));
        vm.prank(actors[ownerSeed % actors.length]);
        token.approve(address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordTransfer(from, to, amount);
    }

    function _recordTransfer(address from, address to, uint256 amount) internal {
        // Aliasing is explicit and arithmetic checked, unlike the token's unchecked storage updates.
        if (from != to) {
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
        }
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract ZeroToOneInvariantTest is Test {
    ZeroToOne token;
    ZeroToOneHandler handler;
    address[] actors;

    function setUp() public {
        token = new ZeroToOne();
        actors.push(address(this));
        actors.push(address(0xA11CE));
        actors.push(address(0xB0B));
        actors.push(address(0xCA7));
        handler = new ZeroToOneHandler(token, actors);

        // Every actor begins funded; finite and infinite delegation are reachable from call one.
        for (uint256 i = 1; i < actors.length; ++i) {
            handler.transfer(0, i, 250_000_000 ether);
        }
        for (uint256 i; i < actors.length; ++i) {
            handler.approve(i, (i + 1) % actors.length, 125_000_000 ether);
            handler.approveUnlimited(i, (i + 2) % actors.length);
        }

        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.approveUnlimited.selector;
        selectors[4] = handler.revoke.selector;
        selectors[5] = handler.transferFullBalance.selector;
        selectors[6] = handler.selfTransfer.selector;
        selectors[7] = handler.rejectOverspend.selector;
        selectors[8] = handler.rejectUnauthorized.selector;
        selectors[9] = handler.rejectZeroReceiver.selector;
        selectors[10] = handler.rejectZeroSpender.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyIsFixed() public view {
        assertEq(token.totalSupply(), 1_000_000_000 ether);
    }

    function invariant_balancesSumToSupply() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, token.totalSupply());
    }

    function invariant_eachBalanceMatchesAuthorizedMovements() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.expectedBalance(actors[i]), "incorrect holder balance");
        }
    }

    function invariant_allowancesMatchApprovalsAndSuccessfulSpends() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.expectedAllowance(actors[i], actors[j]),
                    "incorrect allowance or failed rollback"
                );
            }
        }
    }

    function invariant_noTokensOrApprovalsLeakToUntrackedAddresses() public view {
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(address(0), actors[i]), 0);
            assertEq(token.allowance(actors[i], address(handler)), 0);
        }
    }

    /// @dev Pin a mixed sequence so meaningful delegation, exhaustion, refill and rejection are
    /// guaranteed even when a random sequence happens to choose many zero-amount transfers.
    function test_handlerSequenceExercisesSpendingAndFailureRollback() public {
        handler.transferFrom(1, 0, 2, 1);
        handler.approve(0, 1, 3);
        handler.transferFrom(1, 0, 0, 3);
        handler.rejectUnauthorized(0, 1, 1);
        handler.rejectOverspend(1, 2, type(uint256).max);
        handler.rejectZeroReceiver(2, 3, 1);
        handler.rejectZeroSpender(3, type(uint256).max);
        handler.approveUnlimited(2, 3);
        handler.transferFrom(3, 2, 1, 1);
        handler.revoke(2, 3);
        handler.transferFullBalance(1, 3);
        handler.transferFullBalance(3, 1);
        handler.selfTransfer(1, type(uint256).max);
        invariant_supplyIsFixed();
        invariant_balancesSumToSupply();
        invariant_eachBalanceMatchesAuthorizedMovements();
        invariant_allowancesMatchApprovalsAndSuccessfulSpends();
        invariant_noTokensOrApprovalsLeakToUntrackedAddresses();
    }
}
