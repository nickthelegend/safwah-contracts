// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TokenRegistry} from "../src/TokenRegistry.sol";
import {MockAED} from "../src/MockAED.sol";
import {MockUSDT} from "../src/MockUSDT.sol";
import {MerchantRegistry} from "../src/MerchantRegistry.sol";
import {VATTracker} from "../src/VATTracker.sol";
import {LoyaltyMinter} from "../src/LoyaltyMinter.sol";
import {SafwahSwap} from "../src/SafwahSwap.sol";
import {SettlementRouter} from "../src/SettlementRouter.sol";
import {SafwahPayment} from "../src/SafwahPayment.sol";

/// @notice Deploys the production Safwah stack, configures compliance + roles, seeds the swap
///         AED reserve, and writes addresses to deployments/amoy.json.
///         forge script script/Deploy.s.sol --rpc-url amoy --broadcast --verify
contract Deploy is Script {
    uint256 constant PROTOCOL_FEE_BPS = 50; // 0.5%
    uint256 constant USDT_AED_RATE = 3672500000000000000; // 3.6725 AED per USDT (1e18)
    uint256 constant SWAP_RESERVE = 500_000 ether; // testnet AED liquidity for the swap

    struct Deployed {
        address registry;
        address aed;
        address usdt;
        address merchantRegistry;
        address vatTracker;
        address loyalty;
        address swap;
        address settlement;
        address payment;
    }

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address treasury = vm.envOr("TREASURY_ADDRESS", deployer);

        vm.startBroadcast(deployerKey);

        Deployed memory d;

        // Compliance + tokens
        d.registry = address(new TokenRegistry(deployer));
        d.aed = address(new MockAED());
        d.usdt = address(new MockUSDT());
        TokenRegistry(d.registry).setAedToken(d.aed);
        TokenRegistry(d.registry).setApprovedInput(d.usdt, 6, true);

        // Core protocol
        d.merchantRegistry = address(new MerchantRegistry(deployer));
        d.vatTracker = address(new VATTracker(deployer, d.merchantRegistry));
        d.loyalty = address(new LoyaltyMinter(deployer));
        d.swap = address(new SafwahSwap(deployer, d.registry, treasury));
        SafwahSwap(d.swap).setRate(d.usdt, USDT_AED_RATE);
        d.settlement = address(new SettlementRouter(deployer, d.registry, d.merchantRegistry, treasury));
        d.payment = address(
            new SafwahPayment(deployer, d.registry, d.merchantRegistry, d.vatTracker, d.loyalty, treasury, PROTOCOL_FEE_BPS)
        );

        // Roles: let SafwahPayment record VAT + mint loyalty; wire the swap.
        VATTracker(d.vatTracker).grantRole(VATTracker(d.vatTracker).RECORDER_ROLE(), d.payment);
        LoyaltyMinter(d.loyalty).grantRole(LoyaltyMinter(d.loyalty).MINTER_ROLE(), d.payment);
        SafwahPayment(d.payment).setSwap(d.swap);

        // Seed the swap's AED reserve (testnet: MockAED open mint).
        MockAED(d.aed).mint(d.swap, SWAP_RESERVE);

        vm.stopBroadcast();

        _log(d, deployer, treasury);
        _writeJson(d);
    }

    function _log(Deployed memory d, address deployer, address treasury) internal pure {
        console.log("== Safwah production deployment (Polygon Amoy) ==");
        console.log("Deployer:         ", deployer);
        console.log("Treasury:         ", treasury);
        console.log("TokenRegistry:    ", d.registry);
        console.log("MockAED:          ", d.aed);
        console.log("MockUSDT:         ", d.usdt);
        console.log("MerchantRegistry: ", d.merchantRegistry);
        console.log("VATTracker:       ", d.vatTracker);
        console.log("LoyaltyMinter:    ", d.loyalty);
        console.log("SafwahSwap:       ", d.swap);
        console.log("SettlementRouter: ", d.settlement);
        console.log("SafwahPayment:    ", d.payment);
    }

    function _writeJson(Deployed memory d) internal {
        string memory json = "deployment";
        vm.serializeUint(json, "chainId", block.chainid);
        vm.serializeAddress(json, "TokenRegistry", d.registry);
        vm.serializeAddress(json, "MockAED", d.aed);
        vm.serializeAddress(json, "MockUSDT", d.usdt);
        vm.serializeAddress(json, "MerchantRegistry", d.merchantRegistry);
        vm.serializeAddress(json, "VATTracker", d.vatTracker);
        vm.serializeAddress(json, "LoyaltyMinter", d.loyalty);
        vm.serializeAddress(json, "SafwahSwap", d.swap);
        vm.serializeAddress(json, "SettlementRouter", d.settlement);
        string memory out = vm.serializeAddress(json, "SafwahPayment", d.payment);
        vm.writeJson(out, "./deployments/amoy.json");
    }
}
