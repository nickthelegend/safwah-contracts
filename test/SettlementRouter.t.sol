// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {TokenRegistry} from "../src/TokenRegistry.sol";
import {MockAED} from "../src/MockAED.sol";
import {MerchantRegistry} from "../src/MerchantRegistry.sol";
import {SettlementRouter} from "../src/SettlementRouter.sol";

contract SettlementRouterTest is Test {
    TokenRegistry registry;
    MockAED aed;
    MerchantRegistry mreg;
    SettlementRouter router;

    address merchant = address(0xBEEF);
    address custodian = address(0xC0FFEE);
    address stranger = address(0xCAFE);
    bytes32 bankHash = keccak256("AE070331234567890123456");

    function setUp() public {
        registry = new TokenRegistry(address(this));
        aed = new MockAED();
        registry.setAedToken(address(aed));
        mreg = new MerchantRegistry(address(this));
        router = new SettlementRouter(address(this), address(registry), address(mreg), custodian);

        vm.prank(merchant);
        mreg.registerMerchant("S", "TL", bankHash);

        aed.mint(merchant, 1000 ether);
        vm.prank(merchant);
        aed.approve(address(router), type(uint256).max);
    }

    function test_Request() public {
        vm.prank(merchant);
        uint256 id = router.requestSettlement(500 ether, bankHash);

        assertEq(id, 0);
        assertEq(aed.balanceOf(custodian), 500 ether);
        assertEq(router.pendingSettled(merchant), 500 ether);

        (address m, uint256 amt,, SettlementRouter.Status st,) = router.settlements(0);
        assertEq(m, merchant);
        assertEq(amt, 500 ether);
        assertEq(uint256(st), uint256(SettlementRouter.Status.Requested));
    }

    function test_Request_OnlyMerchant() public {
        vm.prank(stranger);
        vm.expectRevert(bytes("not a merchant"));
        router.requestSettlement(100 ether, bankHash);
    }

    function test_Complete() public {
        vm.prank(merchant);
        router.requestSettlement(500 ether, bankHash);
        router.completeSettlement(0, keccak256("FT-1"));

        (,,, SettlementRouter.Status st,) = router.settlements(0);
        assertEq(uint256(st), uint256(SettlementRouter.Status.Completed));
        assertEq(router.pendingSettled(merchant), 0);
    }

    function test_Cancel_Refunds() public {
        vm.prank(merchant);
        router.requestSettlement(500 ether, bankHash);

        vm.prank(custodian);
        aed.approve(address(router), type(uint256).max);
        router.cancelSettlement(0);

        (,,, SettlementRouter.Status st,) = router.settlements(0);
        assertEq(uint256(st), uint256(SettlementRouter.Status.Cancelled));
        assertEq(aed.balanceOf(merchant), 1000 ether); // fully refunded
        assertEq(router.pendingSettled(merchant), 0);
    }

    function test_Complete_OnlyRole() public {
        vm.prank(merchant);
        router.requestSettlement(500 ether, bankHash);
        vm.prank(stranger);
        vm.expectRevert();
        router.completeSettlement(0, bytes32(0));
    }
}
