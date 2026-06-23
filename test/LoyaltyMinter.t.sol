// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {LoyaltyMinter} from "../src/LoyaltyMinter.sol";

contract LoyaltyMinterTest is Test {
    LoyaltyMinter loyalty;
    address minter = address(0x1234);
    address tourist = address(0x7041);
    address stranger = address(0xCAFE);

    function setUp() public {
        loyalty = new LoyaltyMinter(address(this));
        loyalty.grantRole(loyalty.MINTER_ROLE(), minter);
    }

    function test_Metadata() public view {
        assertEq(loyalty.name(), "Safwah Loyalty");
        assertEq(loyalty.symbol(), "SFL");
        assertEq(loyalty.decimals(), 18);
    }

    function test_Mint() public {
        vm.prank(minter);
        uint256 amount = loyalty.mint(tourist, 100 ether);
        assertEq(amount, 10 ether);
        assertEq(loyalty.getBalance(tourist), 10 ether);
    }

    function test_Mint_OnlyMinter() public {
        vm.prank(stranger);
        vm.expectRevert();
        loyalty.mint(tourist, 100 ether);
    }

    function test_Redeem() public {
        vm.prank(minter);
        loyalty.mint(tourist, 100 ether);
        vm.prank(tourist);
        loyalty.redeem(4 ether);
        assertEq(loyalty.getBalance(tourist), 6 ether);
    }

    function test_SetPartner() public {
        loyalty.setPartner(address(0xBEEF), true);
        assertTrue(loyalty.isPartner(address(0xBEEF)));
    }

    function test_SetMintRate() public {
        loyalty.setMintRate(5);
        vm.prank(minter);
        assertEq(loyalty.mint(tourist, 100 ether), 20 ether);
    }

    function test_Pause_BlocksMint() public {
        loyalty.pause();
        vm.prank(minter);
        vm.expectRevert();
        loyalty.mint(tourist, 100 ether);
    }
}
