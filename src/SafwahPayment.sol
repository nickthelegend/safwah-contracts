// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {TokenRegistry} from "./TokenRegistry.sol";
import {MerchantRegistry} from "./MerchantRegistry.sol";
import {VATTracker} from "./VATTracker.sol";
import {LoyaltyMinter} from "./LoyaltyMinter.sol";
import {SafwahSwap} from "./SafwahSwap.sol";

/// @title SafwahPayment — protocol entry point. Settles a payment to the merchant in the AED
///        Dirham token (minus a capped protocol fee), records VAT, and mints loyalty in one
///        tx. `pay()` takes AED directly; `swapAndPay()` swaps an approved foreign stablecoin
///        to AED first. Token compliance is enforced via TokenRegistry.
contract SafwahPayment is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    uint256 public constant MAX_FEE_BPS = 1000; // 10%

    TokenRegistry public immutable registry;
    MerchantRegistry public immutable merchantRegistry;
    VATTracker public vatTracker;
    LoyaltyMinter public loyaltyMinter;
    SafwahSwap public swap;

    address public treasury;
    uint256 public protocolFeeBps; // 50 = 0.5%

    event PaymentProcessed(
        address indexed tourist,
        address indexed merchant,
        address tokenIn,
        uint256 amountIn,
        uint256 amountAED,
        uint256 vatAmount,
        uint256 loyaltyMinted,
        uint256 timestamp
    );
    event ConfigUpdated();

    constructor(
        address admin,
        address _registry,
        address _merchantRegistry,
        address _vatTracker,
        address _loyaltyMinter,
        address _treasury,
        uint256 _protocolFeeBps
    ) {
        require(
            admin != address(0) && _registry != address(0) && _merchantRegistry != address(0)
                && _vatTracker != address(0) && _loyaltyMinter != address(0) && _treasury != address(0),
            "zero addr"
        );
        require(_protocolFeeBps <= MAX_FEE_BPS, "fee too high");
        registry = TokenRegistry(_registry);
        merchantRegistry = MerchantRegistry(_merchantRegistry);
        vatTracker = VATTracker(_vatTracker);
        loyaltyMinter = LoyaltyMinter(_loyaltyMinter);
        treasury = _treasury;
        protocolFeeBps = _protocolFeeBps;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(FEE_MANAGER_ROLE, admin);
    }

    /// @notice Pay a merchant directly in the AED Dirham token. Requires prior approval.
    function pay(address merchant, uint256 amountAED, string calldata receiptIPFSHash)
        external
        nonReentrant
        whenNotPaused
    {
        require(merchantRegistry.isActiveMerchant(merchant), "merchant not registered");
        require(amountAED > 0, "zero amount");

        address aed = registry.requireAedToken();
        IERC20(aed).safeTransferFrom(msg.sender, address(this), amountAED);
        _settle(msg.sender, merchant, aed, amountAED, amountAED, receiptIPFSHash);
    }

    /// @notice Pay with an approved foreign stablecoin: swap tokenIn → AED, then settle.
    function swapAndPay(
        address tokenIn,
        uint256 amountIn,
        uint256 minAedOut,
        uint256 deadline,
        address merchant,
        string calldata receiptIPFSHash
    ) external nonReentrant whenNotPaused {
        require(address(swap) != address(0), "swap not set");
        require(merchantRegistry.isActiveMerchant(merchant), "merchant not registered");
        require(amountIn > 0, "zero amount");
        require(registry.isApprovedInput(tokenIn), "input not approved");

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).forceApprove(address(swap), amountIn);
        uint256 amountAED = swap.swap(tokenIn, amountIn, minAedOut, deadline); // AED → this contract

        _settle(msg.sender, merchant, tokenIn, amountIn, amountAED, receiptIPFSHash);
    }

    function _settle(
        address tourist,
        address merchant,
        address tokenIn,
        uint256 amountIn,
        uint256 amountAED,
        string calldata receiptIPFSHash
    ) internal {
        address aed = registry.requireAedToken();
        uint256 fee = (amountAED * protocolFeeBps) / 10000;
        uint256 merchantAmount = amountAED - fee;

        IERC20(aed).safeTransfer(merchant, merchantAmount);
        if (fee > 0) {
            IERC20(aed).safeTransfer(treasury, fee);
        }

        vatTracker.recordPurchaseFor(tourist, merchant, amountAED, receiptIPFSHash);
        uint256 loyaltyMinted = loyaltyMinter.mint(tourist, amountAED);
        uint256 vatAmount = (amountAED * vatTracker.vatRateBps()) / 10000;

        emit PaymentProcessed(tourist, merchant, tokenIn, amountIn, amountAED, vatAmount, loyaltyMinted, block.timestamp);
    }

    // --- Config ---

    function setProtocolFee(uint256 bps) external onlyRole(FEE_MANAGER_ROLE) {
        require(bps <= MAX_FEE_BPS, "fee too high");
        protocolFeeBps = bps;
        emit ConfigUpdated();
    }

    function setTreasury(address _treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_treasury != address(0), "zero");
        treasury = _treasury;
        emit ConfigUpdated();
    }

    function setSwap(address _swap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        swap = SafwahSwap(_swap);
        emit ConfigUpdated();
    }

    function setVATTracker(address _vatTracker) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_vatTracker != address(0), "zero");
        vatTracker = VATTracker(_vatTracker);
        emit ConfigUpdated();
    }

    function setLoyaltyMinter(address _loyaltyMinter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_loyaltyMinter != address(0), "zero");
        loyaltyMinter = LoyaltyMinter(_loyaltyMinter);
        emit ConfigUpdated();
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
