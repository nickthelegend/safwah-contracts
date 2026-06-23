// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {TokenRegistry} from "./TokenRegistry.sol";

/// @title SafwahSwap — converts approved foreign stablecoins into the AED Dirham token.
/// @notice Reserve-based: the contract holds AED liquidity and pays out from reserves, so it
///         works with a NON-mintable real Dirham token (not just a mintable mock). Rates are
///         operator-set per input token (oracle-ready), with slippage + deadline protection.
contract SafwahSwap is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant RATE_SETTER_ROLE = keccak256("RATE_SETTER_ROLE");
    bytes32 public constant LIQUIDITY_ROLE = keccak256("LIQUIDITY_ROLE");

    TokenRegistry public immutable registry;
    address public treasury; // receives swapped-in foreign stablecoins

    /// @notice AED (1e18) paid per 1 whole unit of the input token. e.g. USDT → 3.6725e18.
    mapping(address => uint256) public rate;

    event Swapped(address indexed user, address indexed tokenIn, uint256 amountIn, uint256 aedOut);
    event RateUpdated(address indexed token, uint256 rate);
    event TreasuryUpdated(address indexed treasury);
    event ReserveDeposited(address indexed from, uint256 amount);
    event ReserveWithdrawn(address indexed to, uint256 amount);
    event TokenSwept(address indexed token, address indexed to, uint256 amount);

    constructor(address admin, address _registry, address _treasury) {
        require(admin != address(0) && _registry != address(0) && _treasury != address(0), "zero addr");
        registry = TokenRegistry(_registry);
        treasury = _treasury;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(RATE_SETTER_ROLE, admin);
        _grantRole(LIQUIDITY_ROLE, admin);
    }

    function setRate(address token, uint256 rate_) external onlyRole(RATE_SETTER_ROLE) {
        require(registry.isApprovedInput(token), "input not approved");
        rate[token] = rate_;
        emit RateUpdated(token, rate_);
    }

    function setTreasury(address _treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_treasury != address(0), "zero");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    function quote(address tokenIn, uint256 amountIn) public view returns (uint256) {
        require(registry.isApprovedInput(tokenIn), "input not approved");
        uint256 r = rate[tokenIn];
        require(r > 0, "no rate");
        return (amountIn * r) / (10 ** registry.inputDecimals(tokenIn));
    }

    function aedReserve() public view returns (uint256) {
        return IERC20(registry.requireAedToken()).balanceOf(address(this));
    }

    /// @notice Swap `amountIn` of `tokenIn` for AED, sent to the caller.
    ///         Requires prior tokenIn.approve(this, amountIn).
    function swap(address tokenIn, uint256 amountIn, uint256 minAedOut, uint256 deadline)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 aedOut)
    {
        require(block.timestamp <= deadline, "expired");
        require(amountIn > 0, "zero amount");

        aedOut = quote(tokenIn, amountIn);
        require(aedOut >= minAedOut, "slippage");

        address aed = registry.requireAedToken();
        require(IERC20(aed).balanceOf(address(this)) >= aedOut, "insufficient reserve");

        IERC20(tokenIn).safeTransferFrom(msg.sender, treasury, amountIn);
        IERC20(aed).safeTransfer(msg.sender, aedOut);
        emit Swapped(msg.sender, tokenIn, amountIn, aedOut);
    }

    // --- Liquidity management ---

    function depositReserve(uint256 amount) external onlyRole(LIQUIDITY_ROLE) {
        IERC20(registry.requireAedToken()).safeTransferFrom(msg.sender, address(this), amount);
        emit ReserveDeposited(msg.sender, amount);
    }

    function withdrawReserve(address to, uint256 amount) external onlyRole(LIQUIDITY_ROLE) {
        require(to != address(0), "zero");
        IERC20(registry.requireAedToken()).safeTransfer(to, amount);
        emit ReserveWithdrawn(to, amount);
    }

    function sweepToken(address token, address to, uint256 amount) external onlyRole(LIQUIDITY_ROLE) {
        require(to != address(0), "zero");
        IERC20(token).safeTransfer(to, amount);
        emit TokenSwept(token, to, amount);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
