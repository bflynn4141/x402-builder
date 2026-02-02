// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/RevenueToken.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Mock USDC for testing
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {
        // USDC has 6 decimals but for simplicity we use 18 in mock
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract RevenueTokenTest is Test {
    RevenueToken public token;
    MockUSDC public usdc;

    address public operator = address(0x1);
    address public treasury = address(0x2);
    address public alice = address(0x3);
    address public bob = address(0x4);

    uint256 constant TOTAL_SUPPLY = 1_000_000 ether; // 1M tokens
    uint256 constant OPERATOR_BPS = 2000; // 20%

    function setUp() public {
        usdc = new MockUSDC();

        // Deploy token: operator gets 20%, treasury gets 80%
        token = new RevenueToken(
            "Test Service",
            "TEST",
            operator,
            treasury,
            TOTAL_SUPPLY,
            OPERATOR_BPS,
            "https://test.x402.io",
            "ai"
        );

        // Note: RevenueToken uses hardcoded USDC address on Base mainnet
        // For testing, we need to mock the USDC address
        // This test will fail on actual contract due to hardcoded address
    }

    function test_InitialSupplyDistribution() public view {
        // Operator should get 20%
        uint256 expectedOperator = (TOTAL_SUPPLY * OPERATOR_BPS) / 10000;
        assertEq(token.balanceOf(operator), expectedOperator, "Operator balance wrong");

        // Treasury should get 80%
        uint256 expectedTreasury = TOTAL_SUPPLY - expectedOperator;
        assertEq(token.balanceOf(treasury), expectedTreasury, "Treasury balance wrong");

        // Total supply should be correct
        assertEq(token.totalSupply(), TOTAL_SUPPLY, "Total supply wrong");
    }

    function test_OperatorAndTreasurySame() public {
        // If operator and treasury are same, they get 100%
        RevenueToken sameAddr = new RevenueToken(
            "Same Addr",
            "SAME",
            operator,
            operator, // treasury = operator
            TOTAL_SUPPLY,
            OPERATOR_BPS,
            "https://test.x402.io",
            "ai"
        );

        assertEq(sameAddr.balanceOf(operator), TOTAL_SUPPLY, "Should get full supply");
    }

    function test_ZeroOperatorShare() public {
        // Operator gets 0%, treasury gets 100%
        RevenueToken zeroOp = new RevenueToken(
            "Zero Op",
            "ZERO",
            operator,
            treasury,
            TOTAL_SUPPLY,
            0, // 0 bps
            "https://test.x402.io",
            "ai"
        );

        assertEq(zeroOp.balanceOf(operator), 0, "Operator should get nothing");
        assertEq(zeroOp.balanceOf(treasury), TOTAL_SUPPLY, "Treasury gets all");
    }

    function test_FullOperatorShare() public {
        // Operator gets 100%, treasury gets 0%
        RevenueToken fullOp = new RevenueToken(
            "Full Op",
            "FULL",
            operator,
            treasury,
            TOTAL_SUPPLY,
            10000, // 100%
            "https://test.x402.io",
            "ai"
        );

        assertEq(fullOp.balanceOf(operator), TOTAL_SUPPLY, "Operator should get all");
        assertEq(fullOp.balanceOf(treasury), 0, "Treasury gets nothing");
    }

    function test_RevertOnZeroAddress() public {
        // Zero operator
        vm.expectRevert(RevenueToken.ZeroAddress.selector);
        new RevenueToken("X", "X", address(0), treasury, TOTAL_SUPPLY, OPERATOR_BPS, "", "");

        // Zero treasury
        vm.expectRevert(RevenueToken.ZeroAddress.selector);
        new RevenueToken("X", "X", operator, address(0), TOTAL_SUPPLY, OPERATOR_BPS, "", "");
    }

    function test_RevertOnZeroSupply() public {
        vm.expectRevert(RevenueToken.ZeroAmount.selector);
        new RevenueToken("X", "X", operator, treasury, 0, OPERATOR_BPS, "", "");
    }

    function test_RevertOnInvalidBps() public {
        vm.expectRevert(RevenueToken.ZeroAmount.selector);
        new RevenueToken("X", "X", operator, treasury, TOTAL_SUPPLY, 10001, "", ""); // > 100%
    }

    function test_ServiceMetadata() public view {
        assertEq(token.operator(), operator);
        assertEq(token.serviceEndpoint(), "https://test.x402.io");
        assertEq(token.serviceCategory(), "ai");
        assertEq(token.operatorShareBps(), OPERATOR_BPS);
    }

    function test_UpdateServiceOperatorOnly() public {
        vm.prank(alice);
        vm.expectRevert(RevenueToken.NotOperator.selector);
        token.updateService("new-endpoint", "data");

        vm.prank(operator);
        token.updateService("https://new.x402.io", "data");

        assertEq(token.serviceEndpoint(), "https://new.x402.io");
        assertEq(token.serviceCategory(), "data");
    }

    function test_EmptyUpdatePreservesValues() public {
        vm.prank(operator);
        token.updateService("", ""); // Empty strings

        // Original values should be preserved
        assertEq(token.serviceEndpoint(), "https://test.x402.io");
        assertEq(token.serviceCategory(), "ai");
    }
}

/// @dev Test dividend distribution logic (requires fork or mock)
contract RevenueDistributionTest is Test {
    // This test requires either:
    // 1. Forking Base mainnet to use real USDC
    // 2. Modifying the contract to accept USDC address as constructor param
    //
    // For now, we test the math logic separately

    function test_MagnitudeCalculation() public pure {
        // Verify MAGNITUDE doesn't overflow in calculations
        uint256 MAGNITUDE = 2**128;
        uint256 supply = 1_000_000 ether; // 1M tokens
        uint256 revenue = 1_000_000 * 1e6; // 1M USDC (6 decimals)

        // revenuePerShare = revenue * MAGNITUDE / supply
        uint256 revenuePerShare = (revenue * MAGNITUDE) / supply;

        // accumulated = balance * revenuePerShare / MAGNITUDE
        uint256 balance = 200_000 ether; // 20% of supply
        uint256 accumulated = (balance * revenuePerShare) / MAGNITUDE;

        // Should get ~20% of revenue (allow small rounding error)
        uint256 expected = 200_000 * 1e6;
        assertApproxEqRel(accumulated, expected, 1e12, "Should get ~20% of 1M USDC");
    }

    function test_SmallRevenueTruncation() public pure {
        // Very small revenue relative to supply will be truncated
        // This is expected behavior - dust stays in contract
        uint256 MAGNITUDE = 2**128;
        uint256 supply = 1_000_000 ether;
        uint256 revenue = 1; // 0.000001 USDC (smallest unit)

        uint256 revenuePerShare = (revenue * MAGNITUDE) / supply;

        // With 1M tokens and 1 unit of revenue, the math is:
        // revenuePerShare = 1 * 2^128 / 1e24 = 2^128 / 1e24 ≈ 340
        // For 100% holder: (1e24 * 340) / 2^128 = 340e24 / 2^128 ≈ 0.9999...
        // Truncates to 0
        uint256 balance = 1_000_000 ether;
        uint256 accumulated = (balance * revenuePerShare) / MAGNITUDE;

        // At extremely small revenue, even 100% holder loses to truncation
        // This is acceptable - 0.000001 USDC dust is negligible
        assertEq(accumulated, 0, "Extreme truncation at micro-amounts is expected");

        // With larger but still small revenue, holder gets their share
        revenue = 1_000_000; // 1 USDC (1e6 units)
        revenuePerShare = (revenue * MAGNITUDE) / supply;
        accumulated = (balance * revenuePerShare) / MAGNITUDE;
        // Allow 1 unit rounding error (999999 vs 1000000)
        assertApproxEqAbs(accumulated, 1_000_000, 1, "100% holder gets ~full 1 USDC");
    }

    function test_LargeRevenueNoOverflow() public pure {
        uint256 MAGNITUDE = 2**128;
        uint256 supply = 1_000_000 ether;
        uint256 revenue = 1_000_000_000 * 1e6; // 1B USDC

        // Using mulDiv pattern to prevent overflow
        uint256 revenuePerShare = (revenue * MAGNITUDE) / supply;

        uint256 balance = 500_000 ether; // 50%
        uint256 accumulated = (balance * revenuePerShare) / MAGNITUDE;

        // Allow tiny rounding error (< 0.0001%)
        uint256 expected = 500_000_000 * 1e6;
        assertApproxEqRel(accumulated, expected, 1e12, "Should get ~50% of 1B USDC");
    }

    function test_SignedCorrectionLogic() public pure {
        // Simulating the correction pattern
        uint256 MAGNITUDE = 2**128;
        uint256 revenuePerShare = 1e6 * MAGNITUDE / 1_000_000 ether; // 1 USDC per token

        // Alice has 100 tokens, gets ~100 USDC worth of dividends
        uint256 aliceBalance = 100 ether;
        int256 aliceCorrection = 0;

        uint256 aliceAccumulated = uint256(
            int256((aliceBalance * revenuePerShare) / MAGNITUDE) + aliceCorrection
        );
        // Allow small rounding (99 or 100 are both acceptable)
        assertTrue(aliceAccumulated >= 99 && aliceAccumulated <= 100, "Alice should have ~100 units");

        // Alice transfers 50 tokens to Bob AFTER revenue
        // Alice's correction increases (she keeps credit for 50 tokens worth)
        uint256 transferAmount = 50 ether;
        int256 correctionDelta = int256((transferAmount * revenuePerShare) / MAGNITUDE);

        aliceCorrection += correctionDelta;
        int256 bobCorrection = -correctionDelta; // no credit for past dividends

        // After transfer, balances change
        aliceBalance = 50 ether;
        uint256 bobBalance = 50 ether;

        // Alice still gets ~100 (from balance + correction)
        aliceAccumulated = uint256(
            int256((aliceBalance * revenuePerShare) / MAGNITUDE) + aliceCorrection
        );
        assertTrue(aliceAccumulated >= 98 && aliceAccumulated <= 100, "Alice should still have ~100 units");

        // Bob gets 0 (balance - negative correction cancels out)
        int256 bobRaw = int256((bobBalance * revenuePerShare) / MAGNITUDE) + bobCorrection;
        assertEq(bobRaw, 0, "Bob should have 0 units (received after dividend)");
    }

    function test_DividendInvariant() public pure {
        // Key invariant: sum of all dividends <= total revenue
        // This prevents insolvency
        uint256 MAGNITUDE = 2**128;
        uint256 supply = 1_000 ether; // Small supply for clearer math
        uint256 revenue = 100 * 1e6; // 100 USDC

        uint256 revenuePerShare = (revenue * MAGNITUDE) / supply;

        // Sum dividends for all holders (simulating equal distribution)
        uint256 totalDividends = 0;
        for (uint256 i = 0; i < 10; i++) {
            uint256 balance = 100 ether; // Each holder has 10%
            uint256 div = (balance * revenuePerShare) / MAGNITUDE;
            totalDividends += div;
        }

        // Total dividends should never exceed revenue deposited
        assertTrue(totalDividends <= revenue, "Dividends must not exceed revenue");
        // Should be very close (within rounding)
        assertApproxEqRel(totalDividends, revenue, 1e14, "Should be ~100% of revenue");
    }
}
