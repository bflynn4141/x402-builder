// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title RevenueToken
 * @notice ERC-20 with built-in revenue distribution to token holders
 * @dev Implements the "magnified dividend with signed corrections" pattern
 *
 * How it works:
 * 1. Fixed supply is minted at deployment (no inflation)
 * 2. Revenue (USDC) is deposited to this contract
 * 3. Token holders can claim their proportional share anytime
 * 4. Transfers properly preserve pending revenue via signed corrections
 *
 * The key insight: we track a signed correction per account that adjusts
 * when tokens move, ensuring dividends earned before a transfer are preserved.
 */
contract RevenueToken is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    /// @notice USDC contract address (Base mainnet)
    address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    /// @notice Precision multiplier for revenue per token calculations
    uint256 private constant MAGNITUDE = 2**128;

    /// @notice Total revenue distributed (in USDC, 6 decimals)
    uint256 public totalRevenue;

    /// @notice Revenue per token (magnified for precision)
    uint256 private magnifiedRevenuePerShare;

    /// @notice Signed correction per account for accurate dividend tracking
    /// @dev Positive = account owes dividends (received tokens after revenue)
    ///      Negative = account is owed dividends (sent tokens after revenue)
    mapping(address => int256) private magnifiedRevenueCorrections;

    /// @notice Track withdrawn amounts for each address
    mapping(address => uint256) private withdrawnRevenue;

    /// @notice Service operator address
    address public immutable operator;

    /// @notice Service metadata
    string public serviceEndpoint;
    string public serviceCategory;

    event RevenueDeposited(address indexed from, uint256 amount, uint256 newRevenuePerShare);
    event RevenueClaimed(address indexed holder, uint256 amount);
    event ServiceUpdated(string endpoint, string category);

    error ZeroAddress();
    error ZeroAmount();
    error NothingToClaim();
    error NotOperator();

    /// @notice Operator's share of total supply in basis points (e.g., 2000 = 20%)
    uint256 public immutable operatorShareBps;

    /**
     * @param name Token name (e.g., "My AI Service")
     * @param symbol Token symbol (e.g., "MYAI")
     * @param _operator Service operator
     * @param treasury Address to receive non-operator tokens (for sale/distribution)
     * @param totalSupply_ Total fixed supply (18 decimals)
     * @param _operatorShareBps Operator's % of supply in basis points (e.g., 2000 = 20%)
     * @param endpoint Primary x402 endpoint URL
     * @param category Service category (ai, data, tools, etc.)
     */
    constructor(
        string memory name,
        string memory symbol,
        address _operator,
        address treasury,
        uint256 totalSupply_,
        uint256 _operatorShareBps,
        string memory endpoint,
        string memory category
    ) ERC20(name, symbol) {
        if (_operator == address(0)) revert ZeroAddress();
        if (treasury == address(0)) revert ZeroAddress();
        if (totalSupply_ == 0) revert ZeroAmount();
        if (_operatorShareBps > 10000) revert ZeroAmount(); // Using ZeroAmount for invalid bps

        operator = _operator;
        operatorShareBps = _operatorShareBps;
        serviceEndpoint = endpoint;
        serviceCategory = category;

        // Split supply between operator and treasury
        uint256 operatorAmount = (totalSupply_ * _operatorShareBps) / 10000;
        uint256 treasuryAmount = totalSupply_ - operatorAmount;

        _mint(_operator, operatorAmount);
        if (treasuryAmount > 0) {
            _mint(treasury, treasuryAmount);
        }
    }

    /**
     * @notice Deposit revenue to be distributed to token holders
     * @param amount USDC amount (6 decimals)
     */
    function depositRevenue(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 supply = totalSupply();
        if (supply == 0) revert ZeroAmount();

        // Transfer USDC from sender
        IERC20(USDC).safeTransferFrom(msg.sender, address(this), amount);

        totalRevenue += amount;

        // Update revenue per share using mulDiv to prevent overflow
        // magnifiedRevenuePerShare += amount * MAGNITUDE / totalSupply
        magnifiedRevenuePerShare += Math.mulDiv(amount, MAGNITUDE, supply);

        emit RevenueDeposited(msg.sender, amount, magnifiedRevenuePerShare);
    }

    /**
     * @notice Claim pending revenue for caller
     * @return amount USDC amount claimed
     */
    function claim() external nonReentrant returns (uint256 amount) {
        amount = pendingRevenue(msg.sender);
        if (amount == 0) revert NothingToClaim();

        // Update withdrawn amount before transfer (checks-effects-interactions)
        withdrawnRevenue[msg.sender] += amount;

        // Transfer USDC to claimer
        IERC20(USDC).safeTransfer(msg.sender, amount);

        emit RevenueClaimed(msg.sender, amount);
    }

    /**
     * @notice Calculate pending revenue for an address
     * @param account Address to check
     * @return Pending USDC amount (6 decimals)
     */
    function pendingRevenue(address account) public view returns (uint256) {
        return _accumulativeRevenue(account) - withdrawnRevenue[account];
    }

    /**
     * @notice Get total withdrawn by an address
     */
    function totalClaimed(address account) external view returns (uint256) {
        return withdrawnRevenue[account];
    }

    /**
     * @notice Get service stats
     * @return _totalRevenue Total USDC deposited
     * @return _totalSupply Total token supply
     * @return _revenuePerShare Current revenue per share (magnified)
     */
    function getStats() external view returns (
        uint256 _totalRevenue,
        uint256 _totalSupply,
        uint256 _revenuePerShare
    ) {
        return (totalRevenue, totalSupply(), magnifiedRevenuePerShare);
    }

    /**
     * @notice Update service metadata (operator only)
     */
    function updateService(string memory endpoint, string memory category) external {
        if (msg.sender != operator) revert NotOperator();
        if (bytes(endpoint).length > 0) {
            serviceEndpoint = endpoint;
        }
        if (bytes(category).length > 0) {
            serviceCategory = category;
        }
        emit ServiceUpdated(endpoint, category);
    }

    /**
     * @dev Calculate total accumulated revenue for an account (before withdrawals)
     * This uses the signed corrections to properly handle token transfers
     */
    function _accumulativeRevenue(address account) internal view returns (uint256) {
        // accumulated = (balance * magnifiedRevenuePerShare + correction) / MAGNITUDE
        // The correction can be negative, so we do the math carefully
        // Use SafeCast to prevent overflow when casting to int256
        uint256 rawMagnifiedRevenue = balanceOf(account) * magnifiedRevenuePerShare;
        int256 magnifiedRevenue = rawMagnifiedRevenue.toInt256();
        int256 correctedRevenue = magnifiedRevenue + magnifiedRevenueCorrections[account];

        // If corrected revenue is negative (shouldn't happen normally), return 0
        if (correctedRevenue < 0) return 0;

        return uint256(correctedRevenue) / MAGNITUDE;
    }

    /**
     * @dev Override transfer to adjust corrections
     *
     * When tokens move from A to B:
     * - A's correction increases (they no longer own those tokens' future dividends)
     * - B's correction decreases (they don't get credit for past dividends on those tokens)
     *
     * This ensures pending revenue is preserved across transfers.
     */
    function _update(address from, address to, uint256 amount) internal virtual override {
        super._update(from, to, amount);

        // Calculate the magnified correction for this transfer
        // correction = amount * magnifiedRevenuePerShare
        // Use SafeCast to prevent overflow when casting to int256
        uint256 rawCorrection = amount * magnifiedRevenuePerShare;
        int256 magnifiedCorrection = rawCorrection.toInt256();

        if (from != address(0)) {
            // Sender: increase correction (gave up tokens, keeps earned dividends)
            magnifiedRevenueCorrections[from] += magnifiedCorrection;
        }

        if (to != address(0)) {
            // Receiver: decrease correction (got tokens, no credit for past dividends)
            magnifiedRevenueCorrections[to] -= magnifiedCorrection;
        }
    }
}
