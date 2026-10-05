// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ZeroToOne} from "../src/ZeroToOne.sol";

contract ZeroToOneTest is Test {
    ZeroToOne token;

    uint256 constant SUPPLY = 1_000_000_000 ether;
    address constant DEPLOYER = address(0xD0);
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    address constant SPENDER = address(0x5AFE);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new ZeroToOne();
    }

    // --- metadata and supply ---

    function test_metadata() public view {
        assertEq(token.name(), "Zero To One");
        assertEq(token.symbol(), "ZTO");
        assertEq(token.decimals(), 18);
    }

    function test_wholeSupplyMintedToDeployer() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_constructorEmitsMintTransfer() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), ALICE, SUPPLY);
        vm.prank(ALICE);
        new ZeroToOne();
    }

    function test_constructorTakesNoArguments() public pure {
        // The manifest's constructorArgs are empty: creation code is the whole deployment input.
        assertGt(type(ZeroToOne).creationCode.length, 0);
    }

    // --- transfer ---

    function test_transferMovesExactAmount() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(DEPLOYER, ALICE, 100 ether);
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, 100 ether));
        assertEq(token.balanceOf(ALICE), 100 ether);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 100 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferWholeBalance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, SUPPLY);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.balanceOf(DEPLOYER), 0);
    }

    function test_transferZeroSucceeds() public {
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferToSelfChangesNothing() public {
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(DEPLOYER, 5 ether));
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
    }

    function test_transferRevertsOnInsufficientBalance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(ZeroToOne.InsufficientBalance.selector, ALICE, 1 ether, 1 ether + 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1 ether + 1);
    }

    function test_transferRevertsToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroToOne.InvalidReceiver.selector, address(0)));
        vm.prank(DEPLOYER);
        token.transfer(address(0), 1);
    }

    // --- approve / transferFrom ---

    function test_approveSetsAndReplacesAllowance() public {
        vm.expectEmit(true, true, false, true);
        emit Approval(ALICE, SPENDER, 7);
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 7));
        assertEq(token.allowance(ALICE, SPENDER), 7);
        vm.prank(ALICE);
        token.approve(SPENDER, 3);
        assertEq(token.allowance(ALICE, SPENDER), 3);
    }

    function test_approveRevertsForZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroToOne.InvalidSpender.selector, address(0)));
        vm.prank(ALICE);
        token.approve(address(0), 1);
    }

    function test_transferFromSpendsAllowance() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, 10 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, BOB, 4 ether));
        assertEq(token.balanceOf(BOB), 4 ether);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 4 ether);
        assertEq(token.allowance(DEPLOYER, SPENDER), 6 ether);
        assertEq(token.balanceOf(SPENDER), 0);
    }

    function test_transferFromInfiniteAllowanceIsNotDecreased() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, BOB, 4 ether);
        assertEq(token.allowance(DEPLOYER, SPENDER), type(uint256).max);
    }

    function test_transferFromRevertsWithoutAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroToOne.InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, SPENDER, 1);
    }

    function test_transferFromRevertsAboveAllowance() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, 5);
        vm.expectRevert(abi.encodeWithSelector(ZeroToOne.InsufficientAllowance.selector, SPENDER, 5, 6));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, BOB, 6);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromRevertsOnInsufficientBalance() public {
        vm.prank(ALICE);
        token.approve(SPENDER, 5);
        vm.expectRevert(abi.encodeWithSelector(ZeroToOne.InsufficientBalance.selector, ALICE, 0, 5));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 5);
    }

    function test_transferFromRevertsToZeroAddress() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, 5);
        vm.expectRevert(abi.encodeWithSelector(ZeroToOne.InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, address(0), 5);
    }

    /// @dev The deployer has no standing power over a holder: without an allowance it is a stranger.
    function test_deployerCannotMoveAHoldersBalance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(ZeroToOne.InsufficientAllowance.selector, DEPLOYER, 0, 1));
        vm.prank(DEPLOYER);
        token.transferFrom(ALICE, DEPLOYER, 1);
        assertEq(token.balanceOf(ALICE), 10 ether);
    }

    // --- no owner powers, no minting ---

    function test_noAdminSurfaceExists() public {
        string[14] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "owner()",
            "transferOwnership(address)",
            "renounceOwnership()",
            "pause()",
            "unpause()",
            "blacklist(address)",
            "setFee(uint256)",
            "upgradeTo(address)",
            "initialize(address)",
            "setMinter(address)"
        ];
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 10 ether);
        for (uint256 i; i < signatures.length; ++i) {
            vm.prank(DEPLOYER);
            (bool ok,) = address(token).call(abi.encodeWithSignature(signatures[i], ALICE, uint256(1 ether)));
            assertFalse(ok, signatures[i]);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(ALICE), 10 ether);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 10 ether));
    }

    function test_rejectsEther() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok);
        assertEq(address(token).balance, 0);
    }

    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7F) {
                i += op - 0x5F;
                continue;
            }
            assertTrue(op != 0xF4 && op != 0xF2 && op != 0xFF, "forbidden opcode");
        }
    }

    // --- launch split arithmetic, as documented in the README ---

    function test_launchSplitAddsUpToTheSupply() public view {
        uint256 supply = token.totalSupply();
        uint256 swarm = supply * 1_000 / 10_000;
        uint256 pool = supply * 8_800 / 10_000;
        uint256 remainder = supply - swarm - pool;
        assertEq(swarm, 100_000_000 ether);
        assertEq(pool, 880_000_000 ether);
        assertEq(remainder, 20_000_000 ether);
    }

    // --- fuzz ---

    function testFuzz_transferConservesBalances(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != DEPLOYER);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(DEPLOYER);
        token.transfer(to, amount);
        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 held, uint256 amount) public {
        held = bound(held, 0, SUPPLY - 1);
        amount = bound(amount, held + 1, type(uint256).max);
        vm.prank(DEPLOYER);
        token.transfer(ALICE, held);
        vm.expectRevert(abi.encodeWithSelector(ZeroToOne.InsufficientBalance.selector, ALICE, held, amount));
        vm.prank(ALICE);
        token.transfer(BOB, amount);
    }

    function testFuzz_transferFromRespectsAllowance(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, type(uint256).max - 1);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(DEPLOYER);
        token.approve(SPENDER, approved);
        if (amount > approved) {
            vm.expectRevert(abi.encodeWithSelector(ZeroToOne.InsufficientAllowance.selector, SPENDER, approved, amount));
            vm.prank(SPENDER);
            token.transferFrom(DEPLOYER, BOB, amount);
        } else {
            vm.prank(SPENDER);
            token.transferFrom(DEPLOYER, BOB, amount);
            assertEq(token.balanceOf(BOB), amount);
            assertEq(token.allowance(DEPLOYER, SPENDER), approved - amount);
        }
    }
}
