// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ZeroToOne} from "../src/ZeroToOne.sol";

/// @dev Moves tokens among a fixed set of actors through every state-changing entry point.
contract ZeroToOneHandler is Test {
    ZeroToOne public immutable token;
    address[] public actors;

    constructor(ZeroToOne token_, address[] memory actors_) {
        token = token_;
        actors = actors_;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        token.transfer(to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        vm.prank(actors[ownerSeed % actors.length]);
        token.approve(actors[spenderSeed % actors.length], amount);
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 limit = token.balanceOf(from);
        uint256 allowed = token.allowance(from, spender);
        if (allowed < limit) limit = allowed;
        amount = bound(amount, 0, limit);
        vm.prank(spender);
        token.transferFrom(from, to, amount);
    }
}

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
        targetContract(address(handler));
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
}
