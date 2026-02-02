// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title RevenueSplitter
 * @notice Forwards x402 payments to RevenueToken for distribution
 * @dev This is the payment receiver for x402 services
 *
 * Flow:
 * 1. x402 payments (USDC) go to this contract
 * 2. Anyone can call split() to forward to RevenueToken
 * 3. 100% goes to token holders (operator earns via token ownership)
 *
 * Economics:
 * - Operator receives X% of token supply at mint time
 * - Operator earns X% of all revenue by holding X% of tokens
 * - No special "operator fee" - just proportional token ownership
 */
contract RevenueSplitter is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice USDC contract address (Base mainnet)
    address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    /// @notice The RevenueToken that receives all revenue
    address public immutable revenueToken;

    /// @notice Total USDC forwarded to token holders
    uint256 public totalForwarded;

    event RevenueForwarded(uint256 amount, address indexed caller);

    error ZeroAddress();
    error NothingToForward();

    /**
     * @param _revenueToken The RevenueToken contract address
     */
    constructor(address _revenueToken) {
        if (_revenueToken == address(0)) revert ZeroAddress();
        revenueToken = _revenueToken;

        // Pre-approve RevenueToken to pull USDC
        IERC20(USDC).forceApprove(_revenueToken, type(uint256).max);
    }

    /**
     * @notice Forward any pending USDC to the RevenueToken
     * @dev Anyone can call this (incentivized by token holders)
     * @return amount Amount forwarded to RevenueToken
     */
    function split() external nonReentrant returns (uint256 amount) {
        amount = IERC20(USDC).balanceOf(address(this));
        if (amount == 0) revert NothingToForward();

        totalForwarded += amount;

        // Forward 100% to RevenueToken for distribution to all holders
        IRevenueToken(revenueToken).depositRevenue(amount);

        emit RevenueForwarded(amount, msg.sender);
    }

    /**
     * @notice Get pending balance to forward
     */
    function pending() external view returns (uint256) {
        return IERC20(USDC).balanceOf(address(this));
    }

    /**
     * @notice Get stats
     */
    function getStats() external view returns (
        uint256 _totalForwarded,
        uint256 _pending
    ) {
        return (totalForwarded, IERC20(USDC).balanceOf(address(this)));
    }
}

interface IRevenueToken {
    function depositRevenue(uint256 amount) external;
}
