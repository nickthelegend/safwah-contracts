// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerchantRegistry} from "./MerchantRegistry.sol";

/// @title VATTracker — records purchases and tracks claimable VAT with an immediate/airport
///        escrow split. Per-tourist totals are kept as O(1) accumulators (no unbounded
///        iteration), and claims are batch-capped.
contract VATTracker is AccessControl, Pausable, ReentrancyGuard {
    bytes32 public constant RECORDER_ROLE = keccak256("RECORDER_ROLE"); // SafwahPayment
    bytes32 public constant AIRPORT_ROLE = keccak256("AIRPORT_ROLE");

    uint256 public constant MAX_BATCH = 100;

    uint256 public vatRateBps = 500; // 5%
    uint256 public immediateReleaseBps = 8000; // 80% released on claim; remainder at airport

    struct VATRecord {
        address merchant;
        uint256 amountAED;
        uint256 vatAmount;
        uint64 timestamp;
        string receiptIPFSHash;
        bool isClaimed;
    }

    MerchantRegistry public immutable merchantRegistry;

    mapping(address => VATRecord[]) private touristRecords;
    mapping(address => uint256) public totalSpend; // O(1) accumulator
    mapping(address => uint256) public totalVAT; // O(1) accumulator
    mapping(address => uint256) public releasedVAT; // claimable now
    mapping(address => uint256) public heldVAT; // escrowed until airport clearance

    event PurchaseRecorded(
        address indexed tourist, address indexed merchant, uint256 recordId, uint256 amountAED, uint256 vatAmount
    );
    event VATClaimed(address indexed tourist, uint256 vatTotal, uint256 released, uint256 held);
    event AirportCleared(address indexed tourist, uint256 releasedAmount);
    event VatParamsUpdated(uint256 vatRateBps, uint256 immediateReleaseBps);

    constructor(address admin, address registry) {
        require(admin != address(0) && registry != address(0), "zero addr");
        merchantRegistry = MerchantRegistry(registry);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(AIRPORT_ROLE, admin);
    }

    function setVatParams(uint256 _vatRateBps, uint256 _immediateReleaseBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_vatRateBps <= 2000, "vat too high"); // cap 20%
        require(_immediateReleaseBps <= 10000, "bps > 100%");
        vatRateBps = _vatRateBps;
        immediateReleaseBps = _immediateReleaseBps;
        emit VatParamsUpdated(_vatRateBps, _immediateReleaseBps);
    }

    /// @notice Called directly by a registered merchant (merchant == msg.sender).
    function recordPurchase(address tourist, uint256 amountAED, string calldata receiptIPFSHash)
        external
        whenNotPaused
        returns (uint256)
    {
        require(merchantRegistry.isActiveMerchant(msg.sender), "not a merchant");
        return _record(tourist, msg.sender, amountAED, receiptIPFSHash);
    }

    /// @notice Called by the SafwahPayment orchestrator (RECORDER_ROLE) on a merchant's behalf.
    function recordPurchaseFor(address tourist, address merchant, uint256 amountAED, string calldata receiptIPFSHash)
        external
        onlyRole(RECORDER_ROLE)
        whenNotPaused
        returns (uint256)
    {
        require(merchantRegistry.isActiveMerchant(merchant), "not a merchant");
        return _record(tourist, merchant, amountAED, receiptIPFSHash);
    }

    function _record(address tourist, address merchant, uint256 amountAED, string calldata receiptIPFSHash)
        internal
        returns (uint256 recordId)
    {
        require(tourist != address(0), "zero tourist");
        require(amountAED > 0, "zero amount");

        uint256 vatAmount = (amountAED * vatRateBps) / 10000;
        touristRecords[tourist].push(
            VATRecord({
                merchant: merchant,
                amountAED: amountAED,
                vatAmount: vatAmount,
                timestamp: uint64(block.timestamp),
                receiptIPFSHash: receiptIPFSHash,
                isClaimed: false
            })
        );
        recordId = touristRecords[tourist].length - 1;
        totalSpend[tourist] += amountAED;
        totalVAT[tourist] += vatAmount;
        emit PurchaseRecorded(tourist, merchant, recordId, amountAED, vatAmount);
    }

    /// @notice Bundle unclaimed records and claim their VAT (immediate split now, rest held).
    function bundleAndClaim(uint256[] calldata recordIds)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 vatTotal)
    {
        require(recordIds.length > 0 && recordIds.length <= MAX_BATCH, "bad batch");
        VATRecord[] storage records = touristRecords[msg.sender];
        for (uint256 i = 0; i < recordIds.length; i++) {
            uint256 id = recordIds[i];
            require(id < records.length, "bad id");
            VATRecord storage r = records[id];
            require(!r.isClaimed, "already claimed");
            r.isClaimed = true;
            vatTotal += r.vatAmount;
        }
        require(vatTotal > 0, "nothing to claim");

        uint256 released = (vatTotal * immediateReleaseBps) / 10000;
        uint256 held = vatTotal - released;
        releasedVAT[msg.sender] += released;
        heldVAT[msg.sender] += held;
        emit VATClaimed(msg.sender, vatTotal, released, held);
    }

    /// @notice Admin releases the escrowed remainder after airport clearance.
    function airportClearance(address tourist) external onlyRole(AIRPORT_ROLE) {
        uint256 held = heldVAT[tourist];
        require(held > 0, "nothing held");
        heldVAT[tourist] = 0;
        releasedVAT[tourist] += held;
        emit AirportCleared(tourist, held);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function getTouristRecords(address tourist) external view returns (VATRecord[] memory) {
        return touristRecords[tourist];
    }

    function recordCount(address tourist) external view returns (uint256) {
        return touristRecords[tourist].length;
    }

    function getTotalClaimable(address tourist) external view returns (uint256) {
        return releasedVAT[tourist];
    }

    /// @return spend total AED spent  @return vat total VAT  @return claimedVAT released  @return pendingVAT remainder
    function getClaimStatus(address tourist)
        external
        view
        returns (uint256 spend, uint256 vat, uint256 claimedVAT, uint256 pendingVAT)
    {
        spend = totalSpend[tourist];
        vat = totalVAT[tourist];
        claimedVAT = releasedVAT[tourist];
        pendingVAT = vat - claimedVAT;
    }
}
