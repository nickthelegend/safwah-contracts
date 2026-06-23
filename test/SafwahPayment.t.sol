// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {TokenRegistry} from "../src/TokenRegistry.sol";
import {MockAED} from "../src/MockAED.sol";
import {MockUSDT} from "../src/MockUSDT.sol";
import {MerchantRegistry} from "../src/MerchantRegistry.sol";
import {VATTracker} from "../src/VATTracker.sol";
import {LoyaltyMinter} from "../src/LoyaltyMinter.sol";
import {SafwahSwap} from "../src/SafwahSwap.sol";
import {SafwahPayment} from "../src/SafwahPayment.sol";

/// Full-stack integration tests for the production protocol.
contract SafwahPaymentTest is Test {
    TokenRegistry registry;
    MockAED aed;
    MockUSDT usdt;
    MerchantRegistry mreg;
    VATTracker vat;
    LoyaltyMinter loyalty;
    SafwahSwap swap;
    SafwahPayment payment;

    address merchant = address(0xBEEF);
    address tourist = address(0x7041);
    address treasury = address(0x74Ea);
    bytes32 bankHash = keccak256("AE00");

    function setUp() public {
        registry = new TokenRegistry(address(this));
        aed = new MockAED();
        usdt = new MockUSDT();
        registry.setAedToken(address(aed));
        registry.setApprovedInput(address(usdt), 6, true);

        mreg = new MerchantRegistry(address(this));
        vat = new VATTracker(address(this), address(mreg));
        loyalty = new LoyaltyMinter(address(this));
        swap = new SafwahSwap(address(this), address(registry), treasury);
        swap.setRate(address(usdt), 3672500000000000000);
        payment = new SafwahPayment(
            address(this), address(registry), address(mreg), address(vat), address(loyalty), treasury, 50
        );

        vat.grantRole(vat.RECORDER_ROLE(), address(payment));
        loyalty.grantRole(loyalty.MINTER_ROLE(), address(payment));
        payment.setSwap(address(swap));
        aed.mint(address(swap), 1_000_000 ether); // swap AED reserve

        vm.prank(merchant);
        mreg.registerMerchant("Dubai Store", "TL-1", bankHash);

        aed.mint(tourist, 1000 ether);
        usdt.mint(tourist, 1000e6);
        vm.startPrank(tourist);
        aed.approve(address(payment), type(uint256).max);
        usdt.approve(address(payment), type(uint256).max);
        vm.stopPrank();
    }

    function test_Pay() public {
        vm.prank(tourist);
        payment.pay(merchant, 100 ether, "r");
        assertEq(aed.balanceOf(merchant), 99.5 ether);
        assertEq(aed.balanceOf(treasury), 0.5 ether);
        assertEq(vat.totalVAT(tourist), 5 ether);
        assertEq(loyalty.getBalance(tourist), 10 ether);
    }

    function test_SwapAndPay() public {
        vm.prank(tourist);
        payment.swapAndPay(address(usdt), 100e6, 367 ether, block.timestamp + 1, merchant, "r");

        uint256 amountAED = 367.25 ether;
        uint256 fee = (amountAED * 50) / 10000;
        assertEq(aed.balanceOf(merchant), amountAED - fee);
        assertEq(aed.balanceOf(treasury), fee);
        assertEq(usdt.balanceOf(treasury), 100e6);
        assertEq(vat.totalVAT(tourist), (amountAED * 500) / 10000);
        assertEq(loyalty.getBalance(tourist), amountAED / 10);
    }

    function test_Pay_UnregisteredReverts() public {
        vm.prank(tourist);
        vm.expectRevert(bytes("merchant not registered"));
        payment.pay(address(0xDEAD), 100 ether, "r");
    }

    function test_Pay_PausedReverts() public {
        payment.pause();
        vm.prank(tourist);
        vm.expectRevert();
        payment.pay(merchant, 100 ether, "r");
    }

    function test_SetFee_Cap() public {
        vm.expectRevert(bytes("fee too high"));
        payment.setProtocolFee(1001);
    }

    function testFuzz_Pay(uint256 amount) public {
        amount = bound(amount, 1e6, 1000 ether);
        aed.mint(tourist, amount);
        vm.prank(tourist);
        payment.pay(merchant, amount, "r");

        uint256 fee = (amount * 50) / 10000;
        assertEq(aed.balanceOf(merchant), amount - fee);
        assertEq(vat.totalVAT(tourist), (amount * 500) / 10000);
    }
}
