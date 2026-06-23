// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {MerchantRegistry} from "../src/MerchantRegistry.sol";

contract MerchantRegistryTest is Test {
    MerchantRegistry registry;
    address merchant = address(0xBEEF);
    address stranger = address(0xCAFE);
    bytes32 bankHash = keccak256("AE070331234567890123456");

    function setUp() public {
        registry = new MerchantRegistry(address(this));
    }

    function test_Register() public {
        vm.prank(merchant);
        registry.registerMerchant("Dubai Store", "TL-1", bankHash);

        MerchantRegistry.MerchantInfo memory m = registry.getMerchant(merchant);
        assertEq(m.name, "Dubai Store");
        assertEq(m.tradeLicense, "TL-1");
        assertEq(m.bankAccountHash, bankHash);
        assertTrue(m.isActive);
        assertFalse(m.isVerified);
        assertGt(m.registeredAt, 0);
        assertTrue(registry.isActiveMerchant(merchant));
        assertFalse(registry.isVerifiedMerchant(merchant));
    }

    function test_Register_EmptyNameReverts() public {
        vm.prank(merchant);
        vm.expectRevert(bytes("empty name"));
        registry.registerMerchant("", "TL-1", bankHash);
    }

    function test_Verify_RoleGated() public {
        vm.prank(merchant);
        registry.registerMerchant("S", "TL", bankHash);

        registry.verifyMerchant(merchant, true);
        assertTrue(registry.isVerifiedMerchant(merchant));

        vm.prank(stranger);
        vm.expectRevert();
        registry.verifyMerchant(merchant, false);
    }

    function test_Suspend() public {
        vm.prank(merchant);
        registry.registerMerchant("S", "TL", bankHash);
        registry.setMerchantActive(merchant, false);
        assertFalse(registry.isActiveMerchant(merchant));
        assertFalse(registry.isVerifiedMerchant(merchant));
    }

    function test_Pause_BlocksRegister() public {
        registry.pause();
        vm.prank(merchant);
        vm.expectRevert();
        registry.registerMerchant("S", "TL", bankHash);
    }
}
