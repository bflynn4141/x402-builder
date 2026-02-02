// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ServiceLauncher.sol";
import "../src/AuctionStepsEncoder.sol";
import "../src/RevenueToken.sol";
import "../src/RevenueSplitter.sol";

/// @dev Mock USDC for testing (will be deployed at the real USDC address)
contract MockUSDC {
    string public name = "USD Coin";
    string public symbol = "USDC";
    uint8 public decimals = 6;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
}

/// @dev Mock LiquidityLauncher for testing
contract MockLiquidityLauncher {
    event DistributionCreated(address token, uint128 amount, address strategy, bytes32 salt);

    address public lastAuction;
    address public lastToken;
    uint128 public lastAmount;
    bytes public lastConfigData;

    function distributeToken(
        address token,
        Distribution calldata distribution,
        bool,
        bytes32 salt
    ) external returns (address) {
        lastToken = token;
        lastAmount = distribution.amount;
        lastConfigData = distribution.configData;

        // Deploy a mock auction contract
        lastAuction = address(new MockAuction(token, distribution.amount));

        // Pull tokens from caller (simulating real behavior)
        IERC20(token).transferFrom(msg.sender, lastAuction, distribution.amount);

        emit DistributionCreated(token, distribution.amount, distribution.strategy, salt);
        return lastAuction;
    }
}

contract MockAuction {
    address public token;
    uint256 public amount;

    constructor(address _token, uint256 _amount) {
        token = _token;
        amount = _amount;
    }
}

/// @dev Mock Registry for testing
contract MockRegistry {
    event ServiceRegistered(address token, address splitter, address operator);

    function registerFor(
        address token,
        address splitter,
        address operator,
        string memory,
        string memory,
        string memory,
        uint256
    ) external {
        emit ServiceRegistered(token, splitter, operator);
    }
}

contract ServiceLauncherTest is Test {
    using AuctionStepsEncoder for uint256;

    ServiceLauncher public launcher;
    MockLiquidityLauncher public mockLauncher;
    MockUSDC public mockUsdc;
    MockRegistry public mockRegistry;

    address public operator = address(0x1);
    address public lbpStrategyFactory = address(0x3);
    address public ccaFactory = address(0x4);
    address public poolManager = address(0x5);

    // Real USDC address on Base that RevenueSplitter expects
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    function setUp() public {
        // Deploy mock USDC and etch it to the real USDC address
        mockUsdc = new MockUSDC();
        vm.etch(USDC, address(mockUsdc).code);

        mockLauncher = new MockLiquidityLauncher();
        mockRegistry = new MockRegistry();
        launcher = new ServiceLauncher(
            address(mockLauncher),
            lbpStrategyFactory,
            ccaFactory,
            poolManager,
            address(mockRegistry)
        );
    }

    function test_LaunchCreatesTokenAndSplitter() public {
        vm.startPrank(operator);

        LaunchParams memory params = _defaultParams();

        (address token, address splitter, address auction) = launcher.launch(params);

        // Verify token deployed
        assertTrue(token != address(0), "Token not deployed");
        assertEq(RevenueToken(token).name(), "Test Service");
        assertEq(RevenueToken(token).symbol(), "TEST");
        assertEq(RevenueToken(token).operator(), operator);

        // Verify splitter deployed
        assertTrue(splitter != address(0), "Splitter not deployed");
        assertEq(RevenueSplitter(splitter).revenueToken(), token);

        // Verify auction created
        assertTrue(auction != address(0), "Auction not created");

        vm.stopPrank();
    }

    function test_OperatorGetsCorrectTokenShare() public {
        vm.startPrank(operator);

        LaunchParams memory params = _defaultParams();
        params.operatorShareBps = 2000; // 20%

        (address token,,) = launcher.launch(params);

        uint256 expectedOperatorAmount = (params.totalSupply * 2000) / 10000;
        assertEq(RevenueToken(token).balanceOf(operator), expectedOperatorAmount);

        vm.stopPrank();
    }

    function test_AuctionReceivesCorrectTokenAmount() public {
        vm.startPrank(operator);

        LaunchParams memory params = _defaultParams();
        params.operatorShareBps = 2000; // 20%

        (address token,, address auction) = launcher.launch(params);

        uint256 expectedAuctionAmount = params.totalSupply - (params.totalSupply * 2000) / 10000;
        assertEq(RevenueToken(token).balanceOf(auction), expectedAuctionAmount);

        vm.stopPrank();
    }

    function test_ZeroOperatorShareSendsAllToAuction() public {
        vm.startPrank(operator);

        LaunchParams memory params = _defaultParams();
        params.operatorShareBps = 0; // 0%

        (address token,, address auction) = launcher.launch(params);

        assertEq(RevenueToken(token).balanceOf(operator), 0);
        assertEq(RevenueToken(token).balanceOf(auction), params.totalSupply);

        vm.stopPrank();
    }

    function test_FullOperatorShareNoAuction() public {
        vm.startPrank(operator);

        LaunchParams memory params = _defaultParams();
        params.operatorShareBps = 10000; // 100%

        (address token,, address auction) = launcher.launch(params);

        assertEq(RevenueToken(token).balanceOf(operator), params.totalSupply);
        assertEq(auction, address(0), "No auction when operator gets 100%");

        vm.stopPrank();
    }

    function test_ServiceTracking() public {
        vm.startPrank(operator);

        LaunchParams memory params = _defaultParams();
        (address token, address splitter, address auction) = launcher.launch(params);

        assertEq(launcher.getServiceCount(), 1);

        ServiceLauncher.LaunchedService memory service = launcher.getService(token);
        assertEq(service.token, token);
        assertEq(service.splitter, splitter);
        assertEq(service.auction, auction);
        assertEq(service.operator, operator);

        vm.stopPrank();
    }

    function test_RevertOnEmptyName() public {
        vm.startPrank(operator);

        LaunchParams memory params = _defaultParams();
        params.name = "";

        vm.expectRevert(ServiceLauncher.InvalidParams.selector);
        launcher.launch(params);

        vm.stopPrank();
    }

    function test_RevertOnZeroSupply() public {
        vm.startPrank(operator);

        LaunchParams memory params = _defaultParams();
        params.totalSupply = 0;

        vm.expectRevert(ServiceLauncher.InvalidParams.selector);
        launcher.launch(params);

        vm.stopPrank();
    }

    function test_RevertOnInvalidOperatorBps() public {
        vm.startPrank(operator);

        LaunchParams memory params = _defaultParams();
        params.operatorShareBps = 10001; // > 100%

        vm.expectRevert(ServiceLauncher.InvalidParams.selector);
        launcher.launch(params);

        vm.stopPrank();
    }

    function test_RevertOnPastAuctionEndBlock() public {
        vm.startPrank(operator);

        LaunchParams memory params = _defaultParams();
        params.auctionEndBlock = uint64(block.number); // Must be > current block

        vm.expectRevert(ServiceLauncher.InvalidParams.selector);
        launcher.launch(params);

        vm.stopPrank();
    }

    function test_RevertOnEmptyAuctionSteps() public {
        vm.startPrank(operator);

        LaunchParams memory params = _defaultParams();
        params.auctionSteps = ""; // Empty steps

        vm.expectRevert(ServiceLauncher.InvalidParams.selector);
        launcher.launch(params);

        vm.stopPrank();
    }

    function test_AuctionParametersEncodedCorrectly() public {
        vm.startPrank(operator);

        LaunchParams memory params = _defaultParams();
        launcher.launch(params);

        // Decode the config data that was passed to the mock launcher
        // New format: (MigratorParameters, bytes auctionParams)
        bytes memory configData = mockLauncher.lastConfigData();
        (MigratorParameters memory migratorParams, bytes memory auctionParamsBytes) =
            abi.decode(configData, (MigratorParameters, bytes));
        AuctionParameters memory decoded = abi.decode(auctionParamsBytes, (AuctionParameters));

        // Verify MigratorParameters
        assertEq(migratorParams.migrationBlock, params.auctionEndBlock + 1);
        assertEq(migratorParams.currency, params.auctionCurrency);
        assertEq(migratorParams.poolLPFee, 3000);
        assertEq(migratorParams.poolTickSpacing, int24(int256(params.tickSpacing)));
        assertEq(migratorParams.tokenSplit, 1e7); // 100% to LP
        assertEq(migratorParams.initializerFactory, ccaFactory);
        assertEq(migratorParams.positionRecipient, operator);
        assertEq(migratorParams.sweepBlock, params.auctionEndBlock + 1000);
        assertEq(migratorParams.operator, operator);
        assertEq(migratorParams.maxCurrencyAmountForLP, 0);

        // Verify AuctionParameters field order and values
        assertEq(decoded.currency, params.auctionCurrency);
        assertEq(decoded.tokensRecipient, operator);
        assertEq(decoded.fundsRecipient, operator);
        assertEq(decoded.startBlock, uint64(block.number + 1));
        assertEq(decoded.endBlock, params.auctionEndBlock);
        assertEq(decoded.claimBlock, params.auctionEndBlock + 1);
        assertEq(decoded.tickSpacing, params.tickSpacing);
        assertEq(decoded.validationHook, address(0));
        assertEq(decoded.floorPrice, params.floorPrice);
        assertEq(decoded.requiredCurrencyRaised, params.minRaise);
        assertEq(keccak256(decoded.auctionStepsData), keccak256(params.auctionSteps));

        vm.stopPrank();
    }

    function _defaultParams() internal view returns (LaunchParams memory) {
        return LaunchParams({
            name: "Test Service",
            symbol: "TEST",
            totalSupply: 1_000_000 ether,
            operatorShareBps: 2000,
            endpoint: "https://test.x402.io",
            category: "ai",
            salt: bytes32(uint256(1)),
            auctionEndBlock: uint64(block.number + 1000),
            auctionCurrency: address(0), // ETH
            tickSpacing: 100,
            floorPrice: 1e18, // 1 token per ETH
            minRaise: 10 ether,
            auctionSteps: AuctionStepsEncoder.linearRelease(1000)
        });
    }
}

/// @dev Wrapper contract to test library reverts
/// This is needed because library internal functions revert at the same call depth
/// as the test, so vm.expectRevert doesn't work directly
contract AuctionStepsEncoderWrapper {
    function linearRelease(uint256 durationBlocks) external pure returns (bytes memory) {
        return AuctionStepsEncoder.linearRelease(durationBlocks);
    }

    function acceleratingRelease(uint256 totalBlocks) external pure returns (bytes memory) {
        return AuctionStepsEncoder.acceleratingRelease(totalBlocks);
    }

    function customRelease(uint256[2][] memory phases) external pure returns (bytes memory) {
        return AuctionStepsEncoder.customRelease(phases);
    }

    function toQ96Price(uint256 priceNumerator, uint256 priceDenominator) external pure returns (uint256) {
        return AuctionStepsEncoder.toQ96Price(priceNumerator, priceDenominator);
    }

    function floorPriceFromMarketCap(uint256 targetMarketCap, uint256 totalSupply) external pure returns (uint256) {
        return AuctionStepsEncoder.floorPriceFromMarketCap(targetMarketCap, totalSupply);
    }
}

contract AuctionStepsEncoderTest is Test {
    using AuctionStepsEncoder for uint256;

    AuctionStepsEncoderWrapper public wrapper;

    function setUp() public {
        wrapper = new AuctionStepsEncoderWrapper();
    }

    function test_LinearReleaseEncoding() public pure {
        bytes memory steps = AuctionStepsEncoder.linearRelease(1000);

        // Should be 8 bytes (one uint64)
        assertEq(steps.length, 8);

        // Decode and verify
        uint64 step = abi.decode(abi.encodePacked(bytes24(0), steps), (uint64));

        // Extract rate (top 24 bits) and duration (bottom 40 bits)
        uint256 rate = step >> 40;
        uint256 duration = step & ((1 << 40) - 1);

        assertEq(duration, 1000);
        // Rate should be 1e7 / 1000 = 10000 MPS per block
        assertEq(rate, 10000);
    }

    function test_LinearReleaseMinBlocks() public {
        // Should work with exactly 10 blocks
        bytes memory steps = AuctionStepsEncoder.linearRelease(10);
        assertEq(steps.length, 8);
    }

    function test_LinearReleaseRevertOnTooFewBlocks() public {
        vm.expectRevert(AuctionStepsEncoder.InvalidDuration.selector);
        wrapper.linearRelease(9);
    }

    function test_AcceleratingReleaseEncoding() public pure {
        bytes memory steps = AuctionStepsEncoder.acceleratingRelease(1000);

        // Should be 24 bytes (three uint64s)
        assertEq(steps.length, 24);
    }

    function test_AcceleratingReleaseMinBlocks() public {
        // Should work with exactly 100 blocks
        bytes memory steps = AuctionStepsEncoder.acceleratingRelease(100);
        assertEq(steps.length, 24);
    }

    function test_AcceleratingReleaseRevertOnTooFewBlocks() public {
        vm.expectRevert(AuctionStepsEncoder.InvalidDuration.selector);
        wrapper.acceleratingRelease(99);
    }

    function test_ToQ96Price() public pure {
        // 1 token = 0.001 ETH (1e15 wei)
        // Q96 = 1e15 * 2^96 / 1e18 = 2^96 / 1000
        uint256 price = AuctionStepsEncoder.toQ96Price(1e15, 1e18);

        // Verify it's roughly 2^96 / 1000
        uint256 expected = (uint256(1) << 96) / 1000;
        assertApproxEqRel(price, expected, 1e12);
    }

    function test_FloorPriceFromMarketCap() public pure {
        // $1M market cap for 1M tokens = $1 per token
        // In USDC (6 decimals): 1e12 / 1e24 = 1e-12
        // But we need Q96: (1e12 * 2^96) / 1e24

        uint256 price = AuctionStepsEncoder.floorPriceFromMarketCap(1e12, 1_000_000 ether);

        // Should be > 0 (non-zero floor)
        assertTrue(price > 0);
    }

    function test_ToQ96PriceOverflowProtection() public {
        // Very large numerator should revert
        vm.expectRevert("Price overflow");
        wrapper.toQ96Price(2**160, 1);
    }

    function test_FloorPriceOverflowProtection() public {
        // Very large market cap should revert
        vm.expectRevert("MarketCap overflow");
        wrapper.floorPriceFromMarketCap(2**160, 1e18);
    }

    function test_CustomRelease() public pure {
        uint256[2][] memory phases = new uint256[2][](2);
        phases[0] = [uint256(5000), uint256(500)];  // 50% over 500 blocks
        phases[1] = [uint256(5000), uint256(500)];  // 50% over 500 blocks

        bytes memory steps = AuctionStepsEncoder.customRelease(phases);

        // Should be 16 bytes (two uint64s)
        assertEq(steps.length, 16);
    }

    function test_CustomReleaseRevertOnZeroDuration() public {
        uint256[2][] memory phases = new uint256[2][](1);
        phases[0] = [uint256(10000), uint256(0)]; // 100% over 0 blocks = invalid

        vm.expectRevert(AuctionStepsEncoder.InvalidDuration.selector);
        wrapper.customRelease(phases);
    }
}
