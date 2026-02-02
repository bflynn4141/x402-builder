// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./RevenueToken.sol";
import "./RevenueSplitter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ServiceLauncher
 * @notice One-click deployment of tokenized x402 services with CCA auction
 * @dev Deploys RevenueToken + RevenueSplitter, then launches a CCA auction for treasury tokens
 *
 * Flow:
 * 1. Deploy RevenueToken (operator gets X%, this contract gets rest temporarily)
 * 2. Deploy RevenueSplitter (receives x402 payments)
 * 3. Initialize CCA auction via LiquidityLauncher
 * 4. After auction: liquidity auto-seeds on Uniswap v4
 *
 * The operator earns revenue via token ownership. All revenue (100%) goes to holders.
 *
 * Token Distribution Example (20% operator share):
 * ┌──────────────────────────────────────────────────────────────┐
 * │ Total Supply: 1,000,000 tokens                               │
 * │ ├── Operator: 200,000 (20%) - immediate                     │
 * │ └── Auction: 800,000 (80%) - via CCA                        │
 * │     ├── Sold tokens → Uniswap v4 LP (auto-seeded)          │
 * │     ├── Unsold tokens → Operator                            │
 * │     └── Raised funds → Operator                             │
 * └──────────────────────────────────────────────────────────────┘
 */
contract ServiceLauncher {
    using SafeERC20 for IERC20;

    /// @notice LiquidityLauncher for CCA auctions
    ILiquidityLauncher public immutable liquidityLauncher;

    /// @notice LBPStrategy factory address (for CCA)
    address public immutable lbpStrategyFactory;

    /// @notice CCA Factory address (initializer for auctions)
    address public immutable ccaFactory;

    /// @notice Uniswap v4 PoolManager (for pool creation)
    address public immutable poolManager;

    /// @notice ServiceRegistry for discovery
    address public immutable registry;

    /// @notice Track all launched services
    struct LaunchedService {
        address token;
        address splitter;
        address auction;
        address operator;
        uint256 launchedAt;
    }

    LaunchedService[] public services;
    mapping(address => uint256) public tokenToIndex;

    event ServiceLaunched(
        address indexed token,
        address indexed splitter,
        address indexed auction,
        address operator,
        string name,
        string symbol,
        uint256 totalSupply,
        uint256 auctionAmount
    );

    event RegistryFailed(address indexed token, string reason);
    event AuctionSkipped(address indexed token, address indexed operator, uint256 amount, string reason);

    error ZeroAddress();
    error InvalidParams();
    error AuctionFailed();

    /**
     * @param _liquidityLauncher Uniswap LiquidityLauncher address
     * @param _lbpStrategyFactory LBP Strategy Factory for CCA auctions
     * @param _ccaFactory CCA Factory (initializer) address
     * @param _poolManager Uniswap v4 PoolManager address
     * @param _registry ServiceRegistry for auto-registration
     */
    constructor(
        address _liquidityLauncher,
        address _lbpStrategyFactory,
        address _ccaFactory,
        address _poolManager,
        address _registry
    ) {
        if (_liquidityLauncher == address(0)) revert ZeroAddress();
        if (_lbpStrategyFactory == address(0)) revert ZeroAddress();
        if (_ccaFactory == address(0)) revert ZeroAddress();
        if (_poolManager == address(0)) revert ZeroAddress();
        liquidityLauncher = ILiquidityLauncher(_liquidityLauncher);
        lbpStrategyFactory = _lbpStrategyFactory;
        ccaFactory = _ccaFactory;
        poolManager = _poolManager;
        registry = _registry;
    }

    /**
     * @notice Launch a new tokenized x402 service with CCA auction
     * @param params Service and auction configuration
     * @return token RevenueToken address
     * @return splitter RevenueSplitter address (x402 payment receiver)
     * @return auction CCA auction contract address
     */
    function launch(LaunchParams calldata params)
        external
        returns (address token, address splitter, address auction)
    {
        // Validate params
        if (bytes(params.name).length == 0) revert InvalidParams();
        if (params.totalSupply == 0) revert InvalidParams();
        if (params.operatorShareBps > 10000) revert InvalidParams();
        if (params.auctionEndBlock <= block.number) revert InvalidParams();

        // Calculate supply splits
        uint256 operatorAmount = (params.totalSupply * params.operatorShareBps) / 10000;
        uint256 auctionAmount = params.totalSupply - operatorAmount;

        // 1. Deploy RevenueToken
        // Operator gets their share, this contract gets auction tokens temporarily
        bytes32 tokenSalt = keccak256(abi.encodePacked(params.salt, msg.sender, "token"));
        token = address(new RevenueToken{salt: tokenSalt}(
            params.name,
            params.symbol,
            msg.sender,           // operator
            address(this),        // treasury = this contract (temporary holder for auction)
            params.totalSupply,
            params.operatorShareBps,
            params.endpoint,
            params.category
        ));

        // 2. Deploy RevenueSplitter
        bytes32 splitterSalt = keccak256(abi.encodePacked(params.salt, msg.sender, "splitter"));
        splitter = address(new RevenueSplitter{salt: splitterSalt}(token));

        // 3. Initialize CCA Auction via LiquidityLauncher
        if (auctionAmount > 0) {
            // Validate auction params
            if (params.auctionEndBlock >= type(uint64).max) revert InvalidParams();
            if (params.auctionSteps.length == 0) revert InvalidParams();
            if (params.auctionSteps.length % 8 != 0) revert InvalidParams(); // Each step is 8 bytes
            if (params.tickSpacing == 0) revert InvalidParams();

            // Approve LiquidityLauncher to pull tokens
            IERC20(token).forceApprove(address(liquidityLauncher), auctionAmount);

            // Build MigratorParameters for LBP strategy
            MigratorParameters memory migratorParams = MigratorParameters({
                migrationBlock: params.auctionEndBlock + 1,  // Migrate after auction ends
                currency: params.auctionCurrency,
                poolLPFee: 3000,  // 0.3% fee tier
                poolTickSpacing: int24(int256(params.tickSpacing)),
                tokenSplit: 1e7,  // 100% to full-range LP
                initializerFactory: ccaFactory,  // CCA handles the auction
                positionRecipient: msg.sender,  // LP NFT to operator
                sweepBlock: params.auctionEndBlock + 1000,  // Operator can sweep later
                operator: msg.sender,
                maxCurrencyAmountForLP: 0  // No limit
            });

            // Build auction parameters (MUST match CCA factory field order exactly)
            AuctionParameters memory auctionParams = AuctionParameters({
                currency: params.auctionCurrency,
                tokensRecipient: msg.sender,  // Unsold tokens go to operator
                fundsRecipient: msg.sender,   // Raised funds go to operator
                startBlock: uint64(block.number + 1),  // Start next block
                endBlock: params.auctionEndBlock,
                claimBlock: params.auctionEndBlock + 1,  // Claim right after auction
                tickSpacing: params.tickSpacing,
                validationHook: address(0),   // No validation hook
                floorPrice: params.floorPrice,
                requiredCurrencyRaised: params.minRaise,
                auctionStepsData: params.auctionSteps  // MUST BE LAST
            });

            // Encode configData as (MigratorParameters, bytes auctionParams)
            bytes memory configData = abi.encode(migratorParams, abi.encode(auctionParams));

            // Build Distribution struct for LiquidityLauncher
            Distribution memory distribution = Distribution({
                strategy: lbpStrategyFactory,
                amount: uint128(auctionAmount),
                configData: configData
            });

            // Deploy auction via LiquidityLauncher
            // Use try/catch to handle CCA authorization failures gracefully
            bytes32 auctionSalt = keccak256(abi.encodePacked(params.salt, msg.sender, "auction"));
            try liquidityLauncher.distributeToken(
                token,
                distribution,
                false,  // payerIsUser = false (we already have tokens)
                auctionSalt
            ) returns (address _auction) {
                auction = _auction;
                if (auction == address(0)) revert AuctionFailed();
            } catch {
                // CCA creation failed (likely NotActivated or other auth issue)
                // Fallback: send auction tokens to operator instead
                IERC20(token).forceApprove(address(liquidityLauncher), 0); // Clear approval
                IERC20(token).safeTransfer(msg.sender, auctionAmount);
                emit AuctionSkipped(token, msg.sender, auctionAmount, "CCA creation failed");
                // auction remains address(0)
            }
        }

        // 4. Track deployment
        services.push(LaunchedService({
            token: token,
            splitter: splitter,
            auction: auction,
            operator: msg.sender,
            launchedAt: block.timestamp
        }));
        tokenToIndex[token] = services.length;

        // 5. Register in ServiceRegistry if available
        if (registry != address(0)) {
            try IServiceRegistry(registry).registerFor(
                token,
                splitter,
                msg.sender,
                params.name,
                params.category,
                params.endpoint,
                params.operatorShareBps
            ) {} catch {
                emit RegistryFailed(token, "registerFor reverted");
            }
        }

        emit ServiceLaunched(
            token,
            splitter,
            auction,
            msg.sender,
            params.name,
            params.symbol,
            params.totalSupply,
            auctionAmount
        );
    }

    /**
     * @notice Get service count
     */
    function getServiceCount() external view returns (uint256) {
        return services.length;
    }

    /**
     * @notice Get service by token
     */
    function getService(address token) external view returns (LaunchedService memory) {
        uint256 index = tokenToIndex[token];
        require(index > 0, "Service not found");
        return services[index - 1];
    }
}

/**
 * @notice Parameters for launching a service
 */
struct LaunchParams {
    // Token params
    string name;
    string symbol;
    uint256 totalSupply;
    uint256 operatorShareBps;
    string endpoint;
    string category;
    bytes32 salt;

    // Auction params
    uint64 auctionEndBlock;
    address auctionCurrency;     // ETH = address(0), or USDC/WETH address
    uint256 tickSpacing;         // Price granularity
    uint256 floorPrice;          // Minimum price (Q96 format)
    uint128 minRaise;            // Graduation threshold
    bytes auctionSteps;          // Encoded supply schedule
}

/**
 * @notice Auction configuration for CCA
 * @dev MUST match exact field order from Uniswap CCA factory
 */
struct AuctionParameters {
    address currency;              // 1. Token to raise (address(0) = ETH)
    address tokensRecipient;       // 2. Receives unsold tokens
    address fundsRecipient;        // 3. Receives raised funds
    uint64 startBlock;             // 4. Auction start
    uint64 endBlock;               // 5. Auction end
    uint64 claimBlock;             // 6. When claims open
    uint256 tickSpacing;           // 7. Price granularity
    address validationHook;        // 8. Optional bid validator
    uint256 floorPrice;            // 9. Minimum price
    uint128 requiredCurrencyRaised;// 10. Graduation threshold
    bytes auctionStepsData;        // 11. Supply schedule (MUST BE LAST)
}

/**
 * @notice MigratorParameters for LBPStrategy
 * @dev Configures how the LBP strategy migrates to Uniswap v4
 */
struct MigratorParameters {
    uint64 migrationBlock;         // Block when migration can occur
    address currency;              // Paired currency for v4 pool
    uint24 poolLPFee;              // LP fee percentage (e.g., 3000 = 0.3%)
    int24 poolTickSpacing;         // Tick spacing for v4 pool
    uint24 tokenSplit;             // % to LP (1e7 = 100%, rest to one-sided)
    address initializerFactory;    // CCA factory address
    address positionRecipient;     // Receives LP position NFT
    uint64 sweepBlock;             // When operator can sweep
    address operator;              // Sweep authority
    uint128 maxCurrencyAmountForLP;// Max currency for LP (0 = no limit)
}

/**
 * @notice Distribution instruction for LiquidityLauncher
 */
struct Distribution {
    address strategy;     // LBPStrategy factory address
    uint128 amount;       // Tokens to distribute
    bytes configData;     // Encoded (MigratorParameters, bytes auctionParams)
}

/**
 * @notice Interface for Uniswap LiquidityLauncher
 */
interface ILiquidityLauncher {
    function distributeToken(
        address token,
        Distribution calldata distribution,
        bool payerIsUser,
        bytes32 salt
    ) external returns (address distributionContract);
}

/**
 * @notice Interface for ServiceRegistry
 */
interface IServiceRegistry {
    function registerFor(
        address token,
        address splitter,
        address operator,
        string memory name,
        string memory category,
        string memory endpoint,
        uint256 operatorBps
    ) external;
}
