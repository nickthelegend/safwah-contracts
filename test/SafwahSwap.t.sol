// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {TokenRegistry} from "../src/TokenRegistry.sol";
import {MockAED} from "../src/MockAED.sol";
import {MockUSDT} from "../src/MockUSDT.sol";
import {SafwahSwap} from "../src/SafwahSwap.sol";

contract SafwahSwapTest is Test {
    TokenRegistry registry;
    MockAED aed;
    MockUSDT usdt;
    SafwahSwap swap;

    address tourist = address(0x7041);
    address treasury = address(0x74Ea);

    function setUp() public {
        registry = new TokenRegistry(address(this));
        aed = new MockAED();
        usdt = new MockUSDT();
        registry.setAedToken(address(aed));
        registry.setApprovedInput(address(usdt), 6, true);
        swap = new SafwahSwap(address(this), address(registry), treasury);
        swap.setRate(address(usdt), 3672500000000000000); // 3.6725 AED/USDT
        aed.mint(address(swap), 1_000_000 ether); // reserve
        usdt.mint(tourist, 1000e6);
    }

    function test_Quote() public view {
        assertEq(swap.quote(address(usdt), 100e6), 367.25 ether);
    }

    function test_Swap() public {
        vm.startPrank(tourist);
        usdt.approve(address(swap), 100e6);
        uint256 out = swap.swap(address(usdt), 100e6, 367 ether, block.timestamp + 1);
        vm.stopPrank();

        assertEq(out, 367.25 ether);
        assertEq(aed.balanceOf(tourist), 367.25 ether);
        assertEq(usdt.balanceOf(treasury), 100e6);
        assertEq(swap.aedReserve(), 1_000_000 ether - 367.25 ether);
    }

    function test_Swap_SlippageReverts() public {
        vm.startPrank(tourist);
        usdt.approve(address(swap), 100e6);
        vm.expectRevert(bytes("slippage"));
        swap.swap(address(usdt), 100e6, 400 ether, block.timestamp + 1);
        vm.stopPrank();
    }

    function test_Swap_ExpiredReverts() public {
        vm.warp(1000);
        vm.startPrank(tourist);
        usdt.approve(address(swap), 100e6);
        vm.expectRevert(bytes("expired"));
        swap.swap(address(usdt), 100e6, 0, 999);
        vm.stopPrank();
    }

    function test_Swap_InsufficientReserveReverts() public {
        swap.withdrawReserve(address(this), 1_000_000 ether); // drain
        vm.startPrank(tourist);
        usdt.approve(address(swap), 100e6);
        vm.expectRevert(bytes("insufficient reserve"));
        swap.swap(address(usdt), 100e6, 0, block.timestamp + 1);
        vm.stopPrank();
    }

    function test_SetRate_RequiresApprovedInput() public {
        vm.expectRevert(bytes("input not approved"));
        swap.setRate(address(0xDEAD), 1 ether);
    }
}
