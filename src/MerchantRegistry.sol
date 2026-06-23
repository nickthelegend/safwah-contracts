// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title MerchantRegistry — on-chain directory of Safwah merchants with KYC gating.
/// @notice Bank account details are stored only as a `bytes32` hash — never plaintext PII
///         on-chain. The cleartext IBAN lives off-chain (merchant backend) and is matched
///         to the hash at settlement time.
contract MerchantRegistry is AccessControl, Pausable {
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");

    struct MerchantInfo {
        string name;
        string tradeLicense;
        bytes32 bankAccountHash;
        bool isVerified;
        bool isActive;
        uint64 registeredAt;
    }

    mapping(address => MerchantInfo) private merchants;

    event MerchantRegistered(address indexed merchant, string name, string tradeLicense, bytes32 bankAccountHash);
    event MerchantVerified(address indexed merchant, bool verified);
    event MerchantActiveSet(address indexed merchant, bool active);
    event BankAccountUpdated(address indexed merchant, bytes32 bankAccountHash);

    constructor(address admin) {
        require(admin != address(0), "zero admin");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(VERIFIER_ROLE, admin);
    }

    /// @notice Self-register (or update) a merchant. Active immediately, unverified.
    function registerMerchant(string calldata name, string calldata tradeLicense, bytes32 bankAccountHash)
        external
        whenNotPaused
    {
        require(bytes(name).length > 0, "empty name");
        require(bytes(tradeLicense).length > 0, "empty license");

        MerchantInfo storage m = merchants[msg.sender];
        m.name = name;
        m.tradeLicense = tradeLicense;
        m.bankAccountHash = bankAccountHash;
        m.isActive = true;
        if (m.registeredAt == 0) {
            m.registeredAt = uint64(block.timestamp);
        }
        emit MerchantRegistered(msg.sender, name, tradeLicense, bankAccountHash);
    }

    function verifyMerchant(address merchant, bool verified) external onlyRole(VERIFIER_ROLE) {
        require(merchants[merchant].registeredAt != 0, "not registered");
        merchants[merchant].isVerified = verified;
        emit MerchantVerified(merchant, verified);
    }

    /// @notice Suspend or reactivate a merchant (compliance action).
    function setMerchantActive(address merchant, bool active) external onlyRole(VERIFIER_ROLE) {
        require(merchants[merchant].registeredAt != 0, "not registered");
        merchants[merchant].isActive = active;
        emit MerchantActiveSet(merchant, active);
    }

    function updateBankAccount(bytes32 bankAccountHash) external {
        require(merchants[msg.sender].registeredAt != 0, "not registered");
        merchants[msg.sender].bankAccountHash = bankAccountHash;
        emit BankAccountUpdated(msg.sender, bankAccountHash);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function getMerchant(address merchant) external view returns (MerchantInfo memory) {
        return merchants[merchant];
    }

    function isVerifiedMerchant(address merchant) external view returns (bool) {
        MerchantInfo storage m = merchants[merchant];
        return m.isVerified && m.isActive;
    }

    function isActiveMerchant(address merchant) external view returns (bool) {
        MerchantInfo storage m = merchants[merchant];
        return m.isActive && m.registeredAt != 0;
    }
}
