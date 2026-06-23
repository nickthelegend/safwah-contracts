// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {TokenRegistry} from "../src/TokenRegistry.sol";

contract TokenRegistryTest is Test {
    TokenRegistry registry;
    address aed = address(0xAED);
    address usdt = address(0x05D7);
    address stranger = address(0xCAFE);

    function setUp() public {
        registry = new TokenRegistry(address(this));
    }

    function test_SetAedToken() public {
        registry.setAedToken(aed);
        assertEq(registry.aedToken(), aed);
        assertTrue(registry.isApprovedAed(aed));
        assertEq(registry.requireAedToken(), aed);
    }

    function test_SetApprovedInput() public {
        registry.setApprovedInput(usdt, 6, true);
        assertTrue(registry.isApprovedInput(usdt));
        assertEq(registry.inputDecimals(usdt), 6);
    }

    function test_RequireAedToken_RevertsWhenUnset() public {
        vm.expectRevert(bytes("aed token unset"));
        registry.requireAedToken();
    }

    function test_OnlyCompliance() public {
        vm.prank(stranger);
        vm.expectRevert();
        registry.setAedToken(aed);
    }
}
