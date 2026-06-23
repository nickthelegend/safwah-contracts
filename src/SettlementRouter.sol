// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {TokenRegistry} from "./TokenRegistry.sol";
import {MerchantRegistry} from "./MerchantRegistry.sol";

/// @title SettlementRouter — the AED-out rail (pillar 1). A merchant converts on-chain AED
///        into a fiat AED bank payout: AED moves to the licensed custodian (treasury), an
///        off-chain rail wires fiat to the merchant's registered bank account, and the
///        custodian confirms (or cancels + refunds) on-chain.
contract SettlementRouter is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant SETTLEMENT_ROLE = keccak256("SETTLEMENT_ROLE");

    TokenRegistry public immutable registry;
    MerchantRegistry public immutable merchantRegistry;
    address public treasury; // licensed custodian that performs fiat payouts

    enum Status {
        None,
        Requested,
        Completed,
        Cancelled
    }

    struct Settlement {
        address merchant;
        uint256 amount;
        bytes32 bankRefHash;
        Status status;
        uint64 timestamp;
    }

    mapping(uint256 => Settlement) public settlements;
    uint256 public settlementCount;
    mapping(address => uint256) public pendingSettled; // outstanding (requested, not completed)

    event SettlementRequested(uint256 indexed id, address indexed merchant, uint256 amount, bytes32 bankRefHash);
    event SettlementCompleted(uint256 indexed id, address indexed merchant, bytes32 fiatRefHash);
    event SettlementCancelled(uint256 indexed id, address indexed merchant);
    event TreasuryUpdated(address indexed treasury);

    constructor(address admin, address _registry, address _merchantRegistry, address _treasury) {
        require(
            admin != address(0) && _registry != address(0) && _merchantRegistry != address(0) && _treasury != address(0),
            "zero addr"
        );
        registry = TokenRegistry(_registry);
        merchantRegistry = MerchantRegistry(_merchantRegistry);
        treasury = _treasury;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(SETTLEMENT_ROLE, admin);
    }

    function setTreasury(address _treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_treasury != address(0), "zero");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    /// @notice Merchant requests a fiat AED payout. Requires prior aed.approve(this, amount).
    function requestSettlement(uint256 amount, bytes32 bankRefHash)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 id)
    {
        require(merchantRegistry.isActiveMerchant(msg.sender), "not a merchant");
        require(amount > 0, "zero amount");

        address aed = registry.requireAedToken();
        IERC20(aed).safeTransferFrom(msg.sender, treasury, amount);

        id = settlementCount++;
        settlements[id] = Settlement({
            merchant: msg.sender,
            amount: amount,
            bankRefHash: bankRefHash,
            status: Status.Requested,
            timestamp: uint64(block.timestamp)
        });
        pendingSettled[msg.sender] += amount;
        emit SettlementRequested(id, msg.sender, amount, bankRefHash);
    }

    /// @notice Custodian confirms the fiat AED transfer completed (off-chain reference hash).
    function completeSettlement(uint256 id, bytes32 fiatRefHash) external onlyRole(SETTLEMENT_ROLE) {
        Settlement storage s = settlements[id];
        require(s.status == Status.Requested, "not requested");
        s.status = Status.Completed;
        pendingSettled[s.merchant] -= s.amount;
        emit SettlementCompleted(id, s.merchant, fiatRefHash);
    }

    /// @notice Cancel a pending settlement and refund AED to the merchant.
    ///         Requires the treasury to have approved this contract for the refund.
    function cancelSettlement(uint256 id) external onlyRole(SETTLEMENT_ROLE) nonReentrant {
        Settlement storage s = settlements[id];
        require(s.status == Status.Requested, "not requested");
        s.status = Status.Cancelled;
        pendingSettled[s.merchant] -= s.amount;
        IERC20(registry.requireAedToken()).safeTransferFrom(treasury, s.merchant, s.amount);
        emit SettlementCancelled(id, s.merchant);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
