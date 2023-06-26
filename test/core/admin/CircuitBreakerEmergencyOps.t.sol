// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {MockToken} from "../../mocks/MockToken.sol";
import {MockDeFiProtocol} from "../../mocks/MockDeFiProtocol.sol";
import {CircuitBreaker} from "src/core/CircuitBreaker.sol";
import {LimiterLib} from "src/utils/LimiterLib.sol";

contract CircuitBreakerEmergencyOpsTest is Test {
    event FundsReleased(address indexed token);
    event HackerFundsWithdrawn(address indexed hacker, address indexed token, address indexed receiver, uint256 amount);

    MockToken internal token;
    MockToken internal secondToken;
    MockToken internal unlimitedToken;

    address internal NATIVE_ADDRESS_PROXY = address(1);
    CircuitBreaker internal circuitBreaker;
    MockDeFiProtocol internal deFi;

    address internal alice = vm.addr(0x1);
    address internal bob = vm.addr(0x2);
    address internal admin = vm.addr(0x3);

    function setUp() public {
        token = new MockToken("USDC", "USDC");
        circuitBreaker = new CircuitBreaker(admin, 3 days, 4 hours, 5 minutes);
        deFi = new MockDeFiProtocol(address(circuitBreaker));

        address[] memory addresses = new address[](1);
        addresses[0] = address(deFi);

        vm.prank(admin);
        circuitBreaker.addProtectedContracts(addresses);

        vm.prank(admin);
        // Protect USDC with 70% max drawdown per 4 hours
        circuitBreaker.registerToken(address(token), 7000, 1000e18);
        vm.prank(admin);
        circuitBreaker.registerToken(NATIVE_ADDRESS_PROXY, 7000, 1000e18);
        vm.warp(1 hours);
    }

    function test_releaseLockedFunds_ifCallerIsNotAdminShouldFail() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        vm.expectRevert(CircuitBreaker.NotAdmin.selector);
        circuitBreaker.releaseLockedFunds(address(token), recipients);
    }

    function test_releaseLockedFunds_ifNotRateLimitedShouldFail() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        vm.prank(admin);
        vm.expectRevert(CircuitBreaker.NotRateLimited.selector);
        circuitBreaker.releaseLockedFunds(address(token), recipients);
    }

    function test_releaseLockedFunds_ifTokenNotRateLimitedShouldFail() public {
        secondToken = new MockToken("DAI", "DAI");
        vm.prank(admin);
        circuitBreaker.registerToken(address(secondToken), 7000, 1000e18);

        token.mint(alice, 1_000_000e18);

        vm.prank(alice);
        token.approve(address(deFi), 1_000_000e18);

        vm.prank(alice);
        deFi.deposit(address(token), 1_000_000e18);

        int256 withdrawalAmount = 300_001e18;
        vm.warp(5 hours);
        vm.prank(alice);
        deFi.withdrawal(address(token), uint256(withdrawalAmount));
        assertEq(circuitBreaker.isRateLimited(), true);
        assertEq(circuitBreaker.isRateLimitBreeched(address(secondToken)), false);

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        vm.prank(admin);
        vm.expectRevert(CircuitBreaker.TokenNotRateLimited.selector);
        circuitBreaker.releaseLockedFunds(address(secondToken), recipients);
    }

    function test_releaseLockedFunds_ifRecipientHasNoLockedFundsShouldFail() public {
        token.mint(alice, 1_000_000e18);

        vm.prank(alice);
        token.approve(address(deFi), 1_000_000e18);

        vm.prank(alice);
        deFi.deposit(address(token), 1_000_000e18);

        int256 withdrawalAmount = 300_001e18;
        vm.warp(5 hours);
        vm.prank(alice);
        deFi.withdrawal(address(token), uint256(withdrawalAmount));
        assertEq(circuitBreaker.isRateLimited(), true);
        assertEq(circuitBreaker.isRateLimitBreeched(address(token)), true);

        address[] memory recipients = new address[](1);
        recipients[0] = bob;

        vm.prank(admin);
        vm.expectRevert(CircuitBreaker.NoLockedFunds.selector);
        circuitBreaker.releaseLockedFunds(address(token), recipients);
    }

    function test_releaseLockedFunds_shouldBeSuccessful() public {
        token.mint(alice, 1_000_000e18);
        token.mint(bob, 1_000_000e18);

        vm.prank(alice);
        token.approve(address(deFi), 1_000_000e18);

        vm.prank(bob);
        token.approve(address(deFi), 1_000_000e18);

        vm.prank(alice);
        deFi.deposit(address(token), 1_000_000e18);

        vm.prank(bob);
        deFi.deposit(address(token), 1_000_000e18);

        int256 withdrawalAmount = 700_000e18;

        vm.warp(5 hours);

        vm.prank(alice);
        deFi.withdrawal(address(token), uint256(withdrawalAmount));

        assertEq(circuitBreaker.isRateLimited(), true);
        assertEq(circuitBreaker.isRateLimitBreeched(address(token)), true);

        vm.prank(bob);
        deFi.withdrawal(address(token), 1_000_000e18);

        address[] memory recipients = new address[](1);
        recipients[0] = bob;

        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit FundsReleased(address(token));
        circuitBreaker.releaseLockedFunds(address(token), recipients);
        assertEq(token.balanceOf(bob), 1_000_000e18);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(circuitBreaker)), uint256(withdrawalAmount));
        assertEq(token.balanceOf(address(deFi)), 1_000_000e18 - uint256(withdrawalAmount));
    }

    function test_withdrawHackerFunds_ifCallerIsNotAdminShouldFail() public {
        address recipient = makeAddr("hackedFundsRecipient");

        vm.expectRevert(CircuitBreaker.NotAdmin.selector);
        circuitBreaker.withdrawHackerFunds(address(token), alice, recipient);
    }

    function test_withdrawHackerFunds_ifRecipientAddressIsInvalidShouldFail() public {
        vm.prank(admin);
        vm.expectRevert(CircuitBreaker.InvalidRecipientAddress.selector);
        circuitBreaker.withdrawHackerFunds(address(token), alice, address(0));
    }

    function test_withdrawHackerFunds_ifNotRateLimitedShouldFail() public {
        address recipient = makeAddr("hackedFundsRecipient");

        vm.prank(admin);
        vm.expectRevert(CircuitBreaker.NotRateLimited.selector);
        circuitBreaker.withdrawHackerFunds(address(token), alice, recipient);
    }

    function test_withdrawHackerFunds_ifTokenNotRateLimitedShouldFail() public {
        secondToken = new MockToken("DAI", "DAI");
        vm.prank(admin);
        circuitBreaker.registerToken(address(secondToken), 7000, 1000e18);

        token.mint(alice, 1_000_000e18);

        vm.prank(alice);
        token.approve(address(deFi), 1_000_000e18);

        vm.prank(alice);
        deFi.deposit(address(token), 1_000_000e18);

        int256 withdrawalAmount = 300_001e18;
        vm.warp(5 hours);
        vm.prank(alice);
        deFi.withdrawal(address(token), uint256(withdrawalAmount));
        assertEq(circuitBreaker.isRateLimited(), true);
        assertEq(circuitBreaker.isRateLimitBreeched(address(secondToken)), false);

        address recipient = makeAddr("hackedFundsRecipient");

        vm.prank(admin);
        vm.expectRevert(CircuitBreaker.TokenNotRateLimited.selector);
        circuitBreaker.withdrawHackerFunds(address(secondToken), alice, recipient);
    }

    function test_withdrawHackerFunds_ifHackerHasNoLockedFundsShouldFail() public {
        vm.prank(admin);
        circuitBreaker.registerToken(address(secondToken), 7000, 1000e18);

        token.mint(alice, 1_000_000e18);

        vm.prank(alice);
        token.approve(address(deFi), 1_000_000e18);

        vm.prank(alice);
        deFi.deposit(address(token), 1_000_000e18);

        int256 withdrawalAmount = 300_001e18;
        vm.warp(5 hours);
        vm.prank(alice);
        deFi.withdrawal(address(token), uint256(withdrawalAmount));
        assertEq(circuitBreaker.isRateLimited(), true);
        assertEq(circuitBreaker.isRateLimitBreeched(address(token)), true);

        address recipient = makeAddr("hackedFundsRecipient");

        vm.prank(admin);
        vm.expectRevert(CircuitBreaker.NoLockedFunds.selector);
        circuitBreaker.withdrawHackerFunds(address(token), bob, recipient);
    }

    function test_withdrawHackerFunds_shouldBeSuccessful() public {
        token.mint(alice, 1_000_000e18);
        token.mint(bob, 1_000_000e18);

        vm.prank(alice);
        token.approve(address(deFi), 1_000_000e18);

        vm.prank(bob);
        token.approve(address(deFi), 1_000_000e18);

        vm.prank(alice);
        deFi.deposit(address(token), 1_000_000e18);

        vm.prank(bob);
        deFi.deposit(address(token), 1_000_000e18);

        int256 withdrawalAmount1 = 599_999e18;
        int256 withdrawalAmount2 = 150_000e18;

        vm.warp(5 hours);

        vm.startPrank(alice);

        deFi.withdrawal(address(token), uint256(withdrawalAmount1));

        deFi.withdrawal(address(token), uint256(withdrawalAmount2));

        vm.stopPrank();
        assertEq(circuitBreaker.isRateLimited(), true);
        assertEq(circuitBreaker.isRateLimitBreeched(address(token)), true);

        vm.prank(bob);
        deFi.withdrawal(address(token), 1_000_000e18);

        address recipient = makeAddr("hackedFundsRecipient");

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit HackerFundsWithdrawn(alice, address(token), recipient, uint256(withdrawalAmount2));
        circuitBreaker.withdrawHackerFunds(address(token), alice, recipient);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(alice), uint256(withdrawalAmount1));
        assertEq(token.balanceOf(address(circuitBreaker)), 1_000_000e18);
        assertEq(token.balanceOf(address(deFi)), 1_000_000e18 - uint256(withdrawalAmount1) - uint256(withdrawalAmount2));
        assertEq(token.balanceOf(recipient), uint256(withdrawalAmount2));
    }
}
