// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title LoyaltyMinter — Safwah Loyalty (SFL): an ERC20Permit token minted on spend and
///        redeemable for discounts. Minting is restricted to MINTER_ROLE (the SafwahPayment
///        orchestrator).
contract LoyaltyMinter is ERC20, ERC20Permit, AccessControl, Pausable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PARTNER_ADMIN_ROLE = keccak256("PARTNER_ADMIN_ROLE");

    /// @notice AED spent per 1 SFL minted (default 10 → 1 SFL per 10 AED). Configurable.
    uint256 public aedPerToken = 10;
    mapping(address => bool) public isPartner;

    event LoyaltyEarned(address indexed tourist, uint256 amount);
    event LoyaltyRedeemed(address indexed tourist, uint256 amount);
    event PartnerSet(address indexed merchant, bool isPartner);
    event MintRateUpdated(uint256 aedPerToken);

    constructor(address admin) ERC20("Safwah Loyalty", "SFL") ERC20Permit("Safwah Loyalty") {
        require(admin != address(0), "zero admin");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PARTNER_ADMIN_ROLE, admin);
    }

    function setMintRate(uint256 newAedPerToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newAedPerToken > 0, "zero rate");
        aedPerToken = newAedPerToken;
        emit MintRateUpdated(newAedPerToken);
    }

    /// @notice Mint loyalty for a spend. amount = aedAmount / aedPerToken.
    function mint(address tourist, uint256 aedAmount)
        external
        onlyRole(MINTER_ROLE)
        whenNotPaused
        returns (uint256 amount)
    {
        amount = aedAmount / aedPerToken;
        if (amount > 0) {
            _mint(tourist, amount);
            emit LoyaltyEarned(tourist, amount);
        }
    }

    /// @notice Burn SFL to redeem a discount (applied off-chain at settlement).
    function redeem(uint256 amount) external whenNotPaused {
        _burn(msg.sender, amount);
        emit LoyaltyRedeemed(msg.sender, amount);
    }

    function setPartner(address merchant, bool partner) external onlyRole(PARTNER_ADMIN_ROLE) {
        isPartner[merchant] = partner;
        emit PartnerSet(merchant, partner);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function getBalance(address account) external view returns (uint256) {
        return balanceOf(account);
    }
}
