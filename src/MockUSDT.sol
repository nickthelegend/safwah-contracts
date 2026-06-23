// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/// @title MockUSDT — TESTNET foreign stablecoin (6 decimals, like USDT/USDC) with permit.
/// @notice The crypto a tourist arrives with, before swapping to AED. Open mint. Testnet only.
contract MockUSDT is ERC20, ERC20Permit {
    constructor() ERC20("Mock USDT", "USDT") ERC20Permit("Mock USDT") {
        _mint(msg.sender, 1_000_000e6);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function faucet() external {
        _mint(msg.sender, 1_000e6);
    }
}
