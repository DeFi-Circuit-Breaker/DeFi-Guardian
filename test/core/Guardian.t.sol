// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import { MockToken } from "../mocks/MockToken.sol";
import { MockDeFiProtocol } from "../mocks/MockDeFiProtocol.sol";
import { Guardian } from "../../src/core/Guardian.sol";


contract GuadianTest is Test {
    MockToken internal _token;
    MockToken internal _secondToken;
    MockToken internal _unlimitedToken;
    Guardian internal _guardian;
    MockDeFiProtocol internal _deFi;

    // hardhat getSigner() -> vm.addr()
    address internal _alice = vm.addr(0x1);
    address internal _bob = vm.addr(0x2);
    address internal _admin = vm.addr(0x3);

    // hardhat beforeEach -> setUp
    function setUp() public {
        _token = new MockToken("USDC", "USDC");
        _deFi = new MockDeFiProtocol();
        _guardian = new Guardian(_admin, 3 days, 3 hours);

        _deFi.setGuardian(address(_guardian));

        address[] memory addresses = new address[](1);
        addresses[0] = address(_deFi);
        
        vm.prank(_admin);
        _guardian.addGuardedContracts(addresses);

        vm.prank(_admin);
        // Guard USDC with 70% max drawdown per 4 hours
        _guardian.registerToken(address(_token), 700, 4 hours, 1000e18);
        vm.warp(1 hours);
    }

    function testInitialization() public {
        Guardian newGuardian = new Guardian(_admin, 3 days, 3 hours);
        assertEq(newGuardian.admin(), _admin);
        assertEq(newGuardian.rateLimitCooldownPeriod(), 3 days);
        assertEq(newGuardian.gracePeriod(), 3 hours);
    }

    function testMint() public {
        _token.mint(_alice, 2e18);
        assertEq(_token.totalSupply(), _token.balanceOf(_alice));
    }

    function testBurn() public {
        _token.mint(_alice, 10e18);
        assertEq(_token.balanceOf(_alice), 10e18);

        _token.burn(_alice, 8e18);

        assertEq(_token.totalSupply(), 2e18);
        assertEq(_token.balanceOf(_alice), 2e18);
    }

    function testRegisterNewToken() public {
        _secondToken = new MockToken("DAI", "DAI");
        vm.prank(_admin);
        _guardian.registerToken(address(_secondToken), 700, 4 hours, 1000e18);
        (
            uint256 bootstrapAmount,
            uint256 withdrawalPeriod,
            int256 withdrawalRateLimitPerPeriod,
            bool exists
        ) = _guardian.tokensRateLimitInfo(address(_secondToken));
        assertEq(bootstrapAmount, 1000e18);
        assertEq(withdrawalPeriod, 4 hours);
        assertEq(withdrawalRateLimitPerPeriod, 700);
        assertEq(exists, true);

        // Cannot register the same _token twice
        vm.expectRevert();
        vm.prank(_admin);
        _guardian.registerToken(address(_secondToken), 700, 4 hours, 1000e18);
    }

    function testDepositWithDrawNoLimitToken() public {
        _unlimitedToken = new MockToken("DAI", "DAI");
        _unlimitedToken.mint(_alice, 10000e18);

        vm.prank(_alice);
        _unlimitedToken.approve(address(_deFi), 10000e18);

        vm.prank(_alice);
        _deFi.deposit(address(_unlimitedToken), 10000e18);

        assertEq(_guardian.checkIfRateLimitBreeched(address(_unlimitedToken)), false);
        vm.warp(1 hours);
        vm.prank(_alice);
        _deFi.withdraw(address(_unlimitedToken), 10000e18);
        assertEq(_guardian.checkIfRateLimitBreeched(address(_unlimitedToken)), false);
    }

    function testDeposit() public {
        _token.mint(_alice, 10000e18);

        vm.prank(_alice);
        _token.approve(address(_deFi), 10000e18);

        vm.prank(_alice);
        _deFi.deposit(address(_token), 10e18);

        assertEq(_guardian.checkIfRateLimitBreeched(address(_token)), false);

        uint256 head = _guardian.tokenLiquidityHead(address(_token));
        uint256 tail = _guardian.tokenLiquidityTail(address(_token));

        assertEq(head, tail);
        assertEq(_guardian.tokenLiquidityHistoracle(address(_token)), 0);
        assertEq(_guardian.tokenLiquidityWindowAmount(address(_token)), 10e18);

        (uint256 nextTimestamp, int256 amount) = _guardian.tokenLiquidityChanges(
            address(_token),
            head
        );
        assertEq(nextTimestamp, 0);
        assertEq(amount, 10e18);

        vm.warp(1 hours);
        vm.prank(_alice);
        _deFi.deposit(address(_token), 110e18);
        assertEq(_guardian.checkIfRateLimitBreeched(address(_token)), false);
        assertEq(_guardian.tokenLiquidityHistoracle(address(_token)), 0);
        assertEq(_guardian.tokenLiquidityWindowAmount(address(_token)), 120e18);

        // All the previous deposits are now out of the window and accounted for in the historacle
        vm.warp(10 hours);
        vm.prank(_alice);
        _deFi.deposit(address(_token), 10e18);
        assertEq(_guardian.checkIfRateLimitBreeched(address(_token)), false);
        assertEq(_guardian.tokenLiquidityWindowAmount(address(_token)), 10e18);
        assertEq(_guardian.tokenLiquidityHistoracle(address(_token)), 120e18);

        uint256 tailNext = _guardian.tokenLiquidityTail(address(_token));
        uint256 headNext = _guardian.tokenLiquidityHead(address(_token));
        assertEq(headNext, block.timestamp);
        assertEq(tailNext, block.timestamp);
    }

    function testClearBacklog() public {
        _token.mint(_alice, 10000e18);

        vm.prank(_alice);
        _token.approve(address(_deFi), 10000e18);

        vm.prank(_alice);
        _deFi.deposit(address(_token), 1);

        vm.warp(2 hours);
        vm.prank(_alice);
        _deFi.deposit(address(_token), 1);

        vm.warp(3 hours);
        vm.prank(_alice);
        _deFi.deposit(address(_token), 1);

        vm.warp(4 hours);
        vm.prank(_alice);
        _deFi.deposit(address(_token), 1);

        vm.warp(5 hours);
        vm.prank(_alice);
        _deFi.deposit(address(_token), 1);

        vm.warp(6.5 hours);
        _guardian.clearBackLog(address(_token), 10);

        // only deposits from 2.5 hours and later should be in the window
        assertEq(_guardian.tokenLiquidityWindowAmount(address(_token)), 3);
        assertEq(_guardian.tokenLiquidityHistoracle(address(_token)), 2);

        assertEq(_guardian.tokenLiquidityHead(address(_token)), 3 hours);
        assertEq(_guardian.tokenLiquidityTail(address(_token)), 5 hours);
    }

    function testWithdrawls() public {
        _token.mint(_alice, 10000e18);

        vm.prank(_alice);
        _token.approve(address(_deFi), 10000e18);

        vm.prank(_alice);
        _deFi.deposit(address(_token), 100e18);

        vm.warp(1 hours);
        vm.prank(_alice);
        _deFi.withdraw(address(_token), 60e18);
        assertEq(_guardian.checkIfRateLimitBreeched(address(_token)), false);
        assertEq(_guardian.tokenLiquidityWindowAmount(address(_token)), 40e18);
        assertEq(_guardian.tokenLiquidityHistoracle(address(_token)), 0);
        assertEq(_token.balanceOf(_alice), 9960e18);

        // All the previous deposits are now out of the window and accounted for in the historacle
        vm.warp(10 hours);
        vm.prank(_alice);
        _deFi.deposit(address(_token), 10e18);
        assertEq(_guardian.checkIfRateLimitBreeched(address(_token)), false);
        assertEq(_guardian.tokenLiquidityWindowAmount(address(_token)), 10e18);
        assertEq(_guardian.tokenLiquidityHistoracle(address(_token)), 40e18);

        uint256 tailNext = _guardian.tokenLiquidityTail(address(_token));
        uint256 headNext = _guardian.tokenLiquidityHead(address(_token));
        assertEq(headNext, block.timestamp);
        assertEq(tailNext, block.timestamp);
    }

    function testAddAndRemoveGuardedContracts() public {
        MockDeFiProtocol secondDeFi = new MockDeFiProtocol();
        secondDeFi.setGuardian(address(_guardian));

        address[] memory addresses = new address[](1);
        addresses[0] = address(secondDeFi);
        vm.prank(_admin);
        _guardian.addGuardedContracts(addresses);

        assertEq(_guardian.isGuarded(address(secondDeFi)), true);

        vm.prank(_admin);
        _guardian.removeGuardedContracts(addresses);
        assertEq(_guardian.isGuarded(address(secondDeFi)), false);
    }

    function testBreach() public {
        // 1 Million USDC deposited
        _token.mint(_alice, 1_000_000e18);

        vm.prank(_alice);
        _token.approve(address(_deFi), 1_000_000e18);

        vm.prank(_alice);
        _deFi.deposit(address(_token), 1_000_000e18);

        // HACK
        // 300k USDC withdrawn
        int256 withdrawalAmount = 300_001e18;
        vm.warp(5 hours);
        vm.prank(_alice);
        _deFi.withdraw(address(_token), uint(withdrawalAmount));
        assertEq(_guardian.checkIfRateLimitBreeched(address(_token)), true);
        assertEq(_guardian.tokenLiquidityWindowAmount(address(_token)), -withdrawalAmount);
        assertEq(_guardian.tokenLiquidityHistoracle(address(_token)), 1_000_000e18);

        assertEq(_guardian.lockedFunds(address(_alice), address(_token)), uint(withdrawalAmount));
        assertEq(_token.balanceOf(_alice), 0);
        assertEq(_token.balanceOf(address(_guardian)), uint(withdrawalAmount));
        assertEq(_token.balanceOf(address(_deFi)), 1_000_000e18 - uint(withdrawalAmount));

        // Attempts to withdraw more than the limit
        vm.warp(6 hours);
        vm.prank(_alice);
        int256 secondAmount = 10_000e18;
        _deFi.withdraw(address(_token), uint(secondAmount));
        assertEq(_guardian.checkIfRateLimitBreeched(address(_token)), true);
        assertEq(
            _guardian.tokenLiquidityWindowAmount(address(_token)),
            -withdrawalAmount - secondAmount
        );
        assertEq(_guardian.tokenLiquidityHistoracle(address(_token)), 1_000_000e18);

        assertEq(
            _guardian.lockedFunds(address(_alice), address(_token)),
            uint(withdrawalAmount + secondAmount)
        );
        assertEq(_token.balanceOf(_alice), 0);

        // False alarm
        // override the limit and allow claim of funds
        vm.prank(_admin);
        _guardian.overrideLimit();

        vm.warp(7 hours);
        vm.prank(_alice);
        _guardian.claimLockedFunds(address(_token));
        assertEq(_token.balanceOf(_alice), uint(withdrawalAmount + secondAmount));
    }

    function testBreachAndLimitExpired() public {
        // 1 Million USDC deposited
        _token.mint(_alice, 1_000_000e18);

        vm.prank(_alice);
        _token.approve(address(_deFi), 1_000_000e18);

        vm.prank(_alice);
        _deFi.deposit(address(_token), 1_000_000e18);

        // HACK
        // 300k USDC withdrawn
        int256 withdrawalAmount = 300_001e18;
        vm.warp(5 hours);
        vm.prank(_alice);
        _deFi.withdraw(address(_token), uint(withdrawalAmount));
        assertEq(_guardian.checkIfRateLimitBreeched(address(_token)), true);
        assertEq(_guardian.isRateLimited(), true);

        vm.warp(4 days);
        vm.prank(_alice);
        _guardian.overrideExpiredRateLimit();
        assertEq(_guardian.isRateLimited(), false);
    }

    function testAdmin() public {
        assertEq(_guardian.admin(), _admin);
        vm.prank(_admin);
        _guardian.transferAdmin(_bob);
        assertEq(_guardian.admin(), _bob);

        vm.expectRevert();
        vm.prank(_admin);
        _guardian.transferAdmin(_alice);
    }
}
