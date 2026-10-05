// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ZeroToOne} from "src/ZeroToOne.sol";

/// @dev A real contract deployer checks constructor msg.sender without impersonating tx.origin.
contract ZTOFactoryProbe {
    ZeroToOne public immutable token = new ZeroToOne();

    function move(address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

/// forge-config: default.fuzz.runs = 1000
contract ZeroToOneEdgeTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    address internal constant DEPLOYER = address(0xD0);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5AFE);
    address internal constant REMAINDER = 0x7B8C742F2e1eEB3fB2C10d72967Fa6d4a22f0479;

    ZeroToOne internal token;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new ZeroToOne();
    }

    function test_oneWeiTransferEmitsExactEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(DEPLOYER, ALICE, 1);
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, 1));
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 1);
    }

    function test_zeroTransfersEmitAndNeedNeitherBalanceNorAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));

        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroAddressesAreRejectedEvenForZeroAmounts() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroToOne.InvalidReceiver.selector, address(0)));
        vm.prank(ALICE);
        token.transfer(address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(ZeroToOne.InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(ZeroToOne.InvalidSpender.selector, address(0)));
        vm.prank(ALICE);
        token.approve(address(0), 0);

        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.allowance(ALICE, address(0)), 0);
    }

    function test_maximumAmountCannotWrapBalancesOrConsumeUnlimitedAllowance() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, type(uint256).max);
        bytes memory errorData =
            abi.encodeWithSelector(ZeroToOne.InsufficientBalance.selector, DEPLOYER, SUPPLY, type(uint256).max);
        vm.expectRevert(errorData);
        vm.prank(DEPLOYER);
        token.transfer(ALICE, type(uint256).max);
        vm.expectRevert(errorData);
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, ALICE, type(uint256).max);

        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(DEPLOYER, SPENDER), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_exactAllowanceCanMoveWholeSupplyButCannotBeReplayed() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, SUPPLY);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(DEPLOYER, BOB, SUPPLY);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, BOB, SUPPLY));
        assertEq(token.balanceOf(DEPLOYER), 0);
        assertEq(token.balanceOf(BOB), SUPPLY);
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);

        // Refill the owner so the replay fails for authorization, not a lack of tokens.
        vm.prank(BOB);
        token.transfer(DEPLOYER, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(ZeroToOne.InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, BOB, 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_unlimitedApprovalCanBeReplacedThenRevoked() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, type(uint256).max);
        vm.startPrank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, 1));
        assertTrue(token.transferFrom(DEPLOYER, BOB, 7));
        vm.stopPrank();
        assertEq(token.allowance(DEPLOYER, SPENDER), type(uint256).max);

        vm.prank(DEPLOYER);
        token.approve(SPENDER, 2);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, 1));
        assertEq(token.allowance(DEPLOYER, SPENDER), 1);
        vm.prank(DEPLOYER);
        token.approve(SPENDER, 0);
        vm.expectRevert(abi.encodeWithSelector(ZeroToOne.InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, ALICE, 1);
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 9);
        assertEq(token.balanceOf(ALICE), 2);
        assertEq(token.balanceOf(BOB), 7);
    }

    function test_largestFiniteAllowanceIsNotTreatedAsUnlimited() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, type(uint256).max - 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, SPENDER, 1));
        assertEq(token.allowance(DEPLOYER, SPENDER), type(uint256).max - 2);
        assertEq(token.balanceOf(SPENDER), 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 1);
    }

    function test_allowanceIsScopedToBothOwnerAndSpender() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 10);
        vm.prank(DEPLOYER);
        token.approve(SPENDER, 10);

        vm.expectRevert(abi.encodeWithSelector(ZeroToOne.InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(DEPLOYER, BOB, 1);
        vm.expectRevert(abi.encodeWithSelector(ZeroToOne.InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, SPENDER, 1);

        assertEq(token.allowance(DEPLOYER, SPENDER), 10);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 10);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 10);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(SPENDER), 0);
    }

    function test_ownerUsingTransferFromStillNeedsApproval() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroToOne.InsufficientAllowance.selector, DEPLOYER, 0, 1));
        vm.prank(DEPLOYER);
        token.transferFrom(DEPLOYER, ALICE, 1);

        vm.prank(DEPLOYER);
        token.approve(DEPLOYER, SUPPLY);
        vm.prank(DEPLOYER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, SUPPLY));
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.balanceOf(DEPLOYER), 0);
        assertEq(token.allowance(DEPLOYER, DEPLOYER), 0);
    }

    function test_selfTransferStillRequiresSufficientBalance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 1);
        vm.prank(ALICE);
        token.approve(SPENDER, 2);
        bytes memory errorData = abi.encodeWithSelector(ZeroToOne.InsufficientBalance.selector, ALICE, 1, 2);
        vm.expectRevert(errorData);
        vm.prank(ALICE);
        token.transfer(ALICE, 2);
        vm.expectRevert(errorData);
        vm.prank(SPENDER);
        token.transferFrom(ALICE, ALICE, 2);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.allowance(ALICE, SPENDER), 2);
    }

    function test_tokenContractCanReceiveWithoutAReceiverCallback() public {
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(address(token), 1));
        assertEq(token.balanceOf(address(token)), 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_contractFactoryDistributionClaimsAndTradingTransfersAreExact() public {
        ZTOFactoryProbe factory = new ZTOFactoryProbe();
        ZeroToOne launched = factory.token();
        address distributor = address(0xD157);
        address pool = address(0x9001);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(address(this)), 0);

        assertTrue(factory.move(distributor, 100_000_000 ether));
        assertTrue(factory.move(pool, 880_000_000 ether));
        assertTrue(factory.move(REMAINDER, 20_000_000 ether));
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), 100_000_000 ether);
        assertEq(launched.balanceOf(pool), 880_000_000 ether);
        assertEq(launched.balanceOf(REMAINDER), 20_000_000 ether);

        vm.prank(distributor);
        assertTrue(launched.transfer(ALICE, 100_000_000 ether));
        assertEq(launched.balanceOf(distributor), 0);
        assertEq(launched.balanceOf(ALICE), 100_000_000 ether);

        // Token-side buy/sell movements only: no AMM or paired-IMD pricing is mocked.
        vm.prank(pool);
        assertTrue(launched.transfer(BOB, 17 ether));
        assertEq(launched.balanceOf(BOB), 17 ether);
        assertEq(launched.balanceOf(pool), 880_000_000 ether - 17 ether);
        vm.prank(BOB);
        launched.approve(SPENDER, 17 ether);
        vm.prank(SPENDER);
        assertTrue(launched.transferFrom(BOB, pool, 17 ether));
        assertEq(launched.balanceOf(BOB), 0);
        assertEq(launched.balanceOf(pool), 880_000_000 ether);
        assertEq(launched.allowance(BOB, SPENDER), 0);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function testFuzz_insufficientBalanceRollsBackAllowance(uint256 held, uint256 approved, uint256 amount) public {
        held = bound(held, 0, SUPPLY - 1);
        approved = bound(approved, held + 1, type(uint256).max - 1);
        amount = bound(amount, held + 1, approved);
        vm.prank(DEPLOYER);
        token.transfer(ALICE, held);
        vm.prank(ALICE);
        token.approve(SPENDER, approved);
        vm.expectRevert(abi.encodeWithSelector(ZeroToOne.InsufficientBalance.selector, ALICE, held, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.allowance(ALICE, SPENDER), approved);
        assertEq(token.balanceOf(ALICE), held);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - held);

        // A failed attempt must leave the original allowance usable.
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, held));
        assertEq(token.allowance(ALICE, SPENDER), approved - held);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), held);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_invalidReceiverRollsBackAllowance(uint256 approved, uint256 amount) public {
        amount = bound(amount, 0, approved < SUPPLY ? approved : SUPPLY);
        vm.prank(DEPLOYER);
        token.approve(SPENDER, approved);
        vm.expectRevert(abi.encodeWithSelector(ZeroToOne.InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, address(0), amount);
        assertEq(token.allowance(DEPLOYER, SPENDER), approved);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_insufficientAllowancePreservesAllState(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY - 1);
        amount = bound(amount, approved + 1, SUPPLY);
        vm.prank(DEPLOYER);
        token.approve(SPENDER, approved);
        vm.expectRevert(abi.encodeWithSelector(ZeroToOne.InsufficientAllowance.selector, SPENDER, approved, amount));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, BOB, amount);
        assertEq(token.allowance(DEPLOYER, SPENDER), approved);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_roundTripHasNoFeeAndPreservesApprovals(uint256 amount, uint256 approval) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(DEPLOYER);
        token.approve(SPENDER, approval);
        vm.prank(ALICE);
        token.approve(BOB, approval);
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount);
        vm.prank(ALICE);
        assertTrue(token.transfer(DEPLOYER, amount));
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(DEPLOYER, SPENDER), approval);
        assertEq(token.allowance(ALICE, BOB), approval);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_delegatedSelfTransferOnlyConsumesFiniteAllowance(uint256 amount, uint256 approved) public {
        amount = bound(amount, 0, SUPPLY);
        approved = bound(approved, amount, type(uint256).max - 1);
        vm.prank(DEPLOYER);
        token.approve(SPENDER, approved);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(DEPLOYER, DEPLOYER, amount);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, DEPLOYER, amount));
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.allowance(DEPLOYER, SPENDER), approved - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
