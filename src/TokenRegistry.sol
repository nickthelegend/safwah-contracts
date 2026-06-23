// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title TokenRegistry — on-chain compliance allowlist for the Safwah protocol.
/// @notice Single source of truth for which tokens the protocol may touch:
///         - `aedToken`: the canonical AED Dirham Payment Token used for settlement,
///           VAT and loyalty accounting (a CBUAE-approved token such as AE Coin on
///           mainnet, or a mock ERC20 on testnet — same protocol bytecode either way).
///         - approved AED tokens: additional Dirham Payment Tokens accepted at checkout.
///         - approved input tokens: foreign stablecoins (USDT/USDC) allowed as swap inputs.
///         Keeping this in one contract lets compliance be administered without redeploying
///         the rest of the protocol.
contract TokenRegistry is AccessControl {
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");

    /// @notice Canonical AED Dirham Payment Token used for settlement accounting.
    address public aedToken;

    /// @notice Approved AED Dirham Payment Tokens (always includes `aedToken`).
    mapping(address => bool) public isApprovedAed;

    /// @notice Approved foreign input stablecoins and their token decimals.
    mapping(address => bool) public isApprovedInput;
    mapping(address => uint8) public inputDecimals;

    event AedTokenUpdated(address indexed token);
    event ApprovedAedUpdated(address indexed token, bool approved);
    event ApprovedInputUpdated(address indexed token, uint8 decimals, bool approved);

    constructor(address admin) {
        require(admin != address(0), "zero admin");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(COMPLIANCE_ROLE, admin);
    }

    /// @notice Set the canonical AED settlement token. Must be a real/approved Dirham token.
    function setAedToken(address token) external onlyRole(COMPLIANCE_ROLE) {
        require(token != address(0), "zero token");
        aedToken = token;
        isApprovedAed[token] = true;
        emit AedTokenUpdated(token);
        emit ApprovedAedUpdated(token, true);
    }

    function setApprovedAed(address token, bool approved) external onlyRole(COMPLIANCE_ROLE) {
        require(token != address(0), "zero token");
        isApprovedAed[token] = approved;
        emit ApprovedAedUpdated(token, approved);
    }

    function setApprovedInput(address token, uint8 decimals_, bool approved) external onlyRole(COMPLIANCE_ROLE) {
        require(token != address(0), "zero token");
        isApprovedInput[token] = approved;
        if (approved) {
            inputDecimals[token] = decimals_;
        }
        emit ApprovedInputUpdated(token, decimals_, approved);
    }

    /// @notice Reverts if the canonical AED token has not been configured yet.
    function requireAedToken() external view returns (address token) {
        token = aedToken;
        require(token != address(0), "aed token unset");
    }
}
