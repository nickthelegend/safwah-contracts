// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MockAED — TESTNET stand-in for an AED Dirham Payment Token (e.g. AE Coin).
/// @notice 18 decimals + EIP-2612 permit (gasless approvals), like a modern compliant
///         stablecoin. Mint is open so anyone can fund test balances / swap reserves.
///         NOT for production — on mainnet the real Dirham token is used via TokenRegistry.
contract MockAED is ERC20, ERC20Permit, Ownable {
    constructor() ERC20("Mock AED", "AED") ERC20Permit("Mock AED") Ownable(msg.sender) {
        _mint(msg.sender, 1_000_000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function faucet() external {
        _mint(msg.sender, 1_000 ether);
    }
}
