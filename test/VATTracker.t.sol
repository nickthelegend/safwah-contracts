// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {MerchantRegistry} from "../src/MerchantRegistry.sol";
import {VATTracker} from "../src/VATTracker.sol";

contract VATTrackerTest is Test {
    MerchantRegistry registry;
    VATTracker tracker;

    address merchant = address(0xBEEF);
    address tourist = address(0x7041);
    address recorder = address(0x5EC0); // simulates SafwahPayment
    address stranger = address(0xCAFE);
    bytes32 bankHash = keccak256("AE00");

    function setUp() public {
        registry = new MerchantRegistry(address(this));
        tracker = new VATTracker(address(this), address(registry));
        tracker.grantRole(tracker.RECORDER_ROLE(), recorder);
        vm.prank(merchant);
        registry.registerMerchant("S", "TL", bankHash);
    }

    function test_RecordByMerchant_Accumulators() public {
        vm.prank(merchant);
        uint256 id = tracker.recordPurchase(tourist, 100 ether, "r1");
        assertEq(id, 0);
        assertEq(tracker.totalSpend(tourist), 100 ether);
        assertEq(tracker.totalVAT(tourist), 5 ether);
        assertEq(tracker.recordCount(tourist), 1);
    }

    function test_RecordPurchaseFor_RoleGated() public {
        vm.prank(stranger);
        vm.expectRevert();
        tracker.recordPurchaseFor(tourist, merchant, 100 ether, "x");

        vm.prank(recorder);
        tracker.recordPurchaseFor(tourist, merchant, 100 ether, "x");
        assertEq(tracker.totalVAT(tourist), 5 ether);
    }

    function test_BundleClaim_8020_And_Status() public {
        vm.startPrank(merchant);
        tracker.recordPurchase(tourist, 100 ether, "r1");
        tracker.recordPurchase(tourist, 200 ether, "r2");
        vm.stopPrank();

        uint256[] memory ids = new uint256[](2);
        ids[0] = 0;
        ids[1] = 1;
        vm.prank(tourist);
        assertEq(tracker.bundleAndClaim(ids), 15 ether);

        assertEq(tracker.getTotalClaimable(tourist), 12 ether);
        assertEq(tracker.heldVAT(tourist), 3 ether);

        (uint256 s, uint256 v, uint256 c, uint256 p) = tracker.getClaimStatus(tourist);
        assertEq(s, 300 ether);
        assertEq(v, 15 ether);
        assertEq(c, 12 ether);
        assertEq(p, 3 ether);
    }

    function test_Airport() public {
        vm.prank(merchant);
        tracker.recordPurchase(tourist, 100 ether, "r1");
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        vm.prank(tourist);
        tracker.bundleAndClaim(ids);

        tracker.airportClearance(tourist);
        assertEq(tracker.getTotalClaimable(tourist), 5 ether);
        assertEq(tracker.heldVAT(tourist), 0);
    }

    function test_DoubleClaimReverts() public {
        vm.prank(merchant);
        tracker.recordPurchase(tourist, 100 ether, "r1");
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        vm.startPrank(tourist);
        tracker.bundleAndClaim(ids);
        vm.expectRevert(bytes("already claimed"));
        tracker.bundleAndClaim(ids);
        vm.stopPrank();
    }

    function test_Airport_OnlyRole() public {
        vm.prank(stranger);
        vm.expectRevert();
        tracker.airportClearance(tourist);
    }
}
