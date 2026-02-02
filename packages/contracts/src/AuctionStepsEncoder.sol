// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title AuctionStepsEncoder
 * @notice Helper library for encoding CCA auction step schedules
 * @dev Auction steps define how tokens are released over time
 *
 * Each step is a packed uint64:
 * - First 24 bits: per-block issuance rate in MPS (milli-basis points, 1e7 = 100%)
 * - Last 40 bits: duration in blocks for this step
 *
 * Example: Linear release over 1000 blocks
 *   - 10 MPS per block for 1000 blocks = 10,000 MPS total = 100%
 */
library AuctionStepsEncoder {
    uint256 constant MPS_PRECISION = 1e7; // Milli-basis points (100% = 1e7)
    uint256 constant MAX_RATE = 2**24 - 1; // Max value for 24-bit rate
    uint256 constant MAX_DURATION = 2**40 - 1; // Max value for 40-bit duration
    uint256 constant MIN_BLOCKS = 10; // Minimum blocks for safe division

    error InvalidDuration();
    error RateOverflow();
    error DurationOverflow();

    /**
     * @notice Create a simple linear release schedule
     * @param durationBlocks How many blocks the auction runs (minimum 10)
     * @return Encoded steps data for CCA
     */
    function linearRelease(uint256 durationBlocks) internal pure returns (bytes memory) {
        if (durationBlocks < MIN_BLOCKS) revert InvalidDuration();
        if (durationBlocks > MAX_DURATION) revert DurationOverflow();

        // Release 100% evenly over duration
        uint256 ratePerBlock = MPS_PRECISION / durationBlocks;
        if (ratePerBlock > MAX_RATE) revert RateOverflow();

        // Pack into uint64: [24 bits rate][40 bits duration]
        uint64 step = uint64((ratePerBlock << 40) | durationBlocks);

        return abi.encodePacked(step);
    }

    /**
     * @notice Create an accelerating release schedule (slow start, fast finish)
     * @dev Recommended for fair price discovery - later entrants pay more
     * @param totalBlocks Total auction duration (minimum 100 blocks for 3 phases)
     * @return Encoded steps data for CCA
     */
    function acceleratingRelease(uint256 totalBlocks) internal pure returns (bytes memory) {
        // Need at least 100 blocks to safely divide into 3 phases
        if (totalBlocks < 100) revert InvalidDuration();
        if (totalBlocks > MAX_DURATION) revert DurationOverflow();

        // 3 phases: slow (20%), medium (30%), fast (50%)
        uint256 phase1Blocks = totalBlocks * 20 / 100;
        uint256 phase2Blocks = totalBlocks * 30 / 100;
        uint256 phase3Blocks = totalBlocks - phase1Blocks - phase2Blocks;

        // Release 10% in phase 1, 30% in phase 2, 60% in phase 3
        uint256 phase1Rate = (MPS_PRECISION * 10 / 100) / phase1Blocks;
        uint256 phase2Rate = (MPS_PRECISION * 30 / 100) / phase2Blocks;
        uint256 phase3Rate = (MPS_PRECISION * 60 / 100) / phase3Blocks;

        // Validate rates fit in 24 bits
        if (phase1Rate > MAX_RATE || phase2Rate > MAX_RATE || phase3Rate > MAX_RATE) {
            revert RateOverflow();
        }

        uint64 step1 = uint64((phase1Rate << 40) | phase1Blocks);
        uint64 step2 = uint64((phase2Rate << 40) | phase2Blocks);
        uint64 step3 = uint64((phase3Rate << 40) | phase3Blocks);

        return abi.encodePacked(step1, step2, step3);
    }

    /**
     * @notice Create a custom multi-phase release schedule
     * @param phases Array of (share in basis points, duration in blocks)
     *        Share is the % of total tokens released in this phase (100 = 1%)
     *        Sum of all shares should equal 10000 (100%)
     * @return Encoded steps data for CCA
     */
    function customRelease(uint256[2][] memory phases) internal pure returns (bytes memory) {
        if (phases.length == 0) revert InvalidDuration();

        bytes memory result;
        uint256 totalShareBps;

        for (uint256 i = 0; i < phases.length; i++) {
            uint256 shareBps = phases[i][0];     // Share in basis points (100 = 1%)
            uint256 duration = phases[i][1];      // Duration in blocks

            if (duration == 0) revert InvalidDuration();
            if (duration > MAX_DURATION) revert DurationOverflow();

            totalShareBps += shareBps;

            // Convert basis points to MPS, then to per-block rate
            uint256 shareMps = shareBps * 1000;  // bps * 1000 = MPS
            uint256 ratePerBlock = shareMps / duration;

            if (ratePerBlock > MAX_RATE) revert RateOverflow();

            uint64 step = uint64((ratePerBlock << 40) | duration);
            result = abi.encodePacked(result, step);
        }

        // Warn: totalShareBps should ideally sum to 10000, but we don't enforce
        // to allow flexibility. Caller is responsible for correct schedule.

        return result;
    }

    /**
     * @notice Calculate Q96 price from human-readable price
     * @dev Q96 = price * 2^96, used by CCA for fixed-point math
     *      Safe for priceNumerator up to ~1e20 before overflow
     * @param priceNumerator Price numerator (e.g., 1e6 for $1 in USDC units)
     * @param priceDenominator Price denominator (e.g., 1e18 for token decimals)
     * @return Q96 formatted price
     */
    function toQ96Price(uint256 priceNumerator, uint256 priceDenominator)
        internal
        pure
        returns (uint256)
    {
        if (priceDenominator == 0) revert InvalidDuration(); // Reuse error
        // Safe: priceNumerator < 2^160 to avoid overflow when << 96
        require(priceNumerator < 2**160, "Price overflow");
        return (priceNumerator << 96) / priceDenominator;
    }

    /**
     * @notice Calculate floor price for a target market cap
     * @dev Safe for marketCap up to ~1e20 before overflow
     * @param targetMarketCap Target FDV in currency units (e.g., 1e12 for $1M USDC)
     * @param totalSupply Total token supply (18 decimals)
     * @return Q96 formatted floor price
     */
    function floorPriceFromMarketCap(uint256 targetMarketCap, uint256 totalSupply)
        internal
        pure
        returns (uint256)
    {
        if (totalSupply == 0) revert InvalidDuration(); // Reuse error
        require(targetMarketCap < 2**160, "MarketCap overflow");
        return (targetMarketCap << 96) / totalSupply;
    }
}
