# x402 Service Tokenization Contracts

Smart contracts for tokenizing x402 API services with revenue sharing and optional CCA (Continuous Clearing Auction) token launches.

## Overview

This system enables API service operators to:
1. **Tokenize their service** - Create an ERC-20 token representing ownership/revenue rights
2. **Receive payments** - Accept USDC payments via the x402 protocol
3. **Share revenue** - Automatically distribute revenue to all token holders
4. **Bootstrap liquidity** - Optionally launch via Uniswap's CCA for fair price discovery

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                           x402 SERVICE TOKENIZATION ARCHITECTURE                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘

╔═══════════════════════════════════════════════════════════════════════════════════════════╗
║                                    1. SERVICE LAUNCH                                       ║
╚═══════════════════════════════════════════════════════════════════════════════════════════╝

                                    ┌──────────────┐
                                    │   Operator   │
                                    │  (msg.sender)│
                                    └──────┬───────┘
                                           │
                                           │ launch(LaunchParams)
                                           ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              ServiceLauncher Contract                                    │
│  ┌────────────────────────────────────────────────────────────────────────────────────┐ │
│  │                                                                                    │ │
│  │   1. Deploy RevenueToken ──────────────────────────────┐                          │ │
│  │      • name, symbol, totalSupply                       │                          │ │
│  │      • operator gets X% immediately                    │                          │ │
│  │      • launcher holds (100-X)% temporarily             │                          │ │
│  │                                                        ▼                          │ │
│  │   2. Deploy RevenueSplitter ◄────────────────── links to token                    │ │
│  │      • receives x402 payments                                                     │ │
│  │      • splits revenue to holders                                                  │ │
│  │                                                                                   │ │
│  │   3. Create CCA Auction (if tokens for auction > 0)                              │ │
│  │      │                                                                            │ │
│  │      │  try {                                                                     │ │
│  │      │    LiquidityLauncher.distributeToken(...)                                 │ │
│  │      │  } catch {                                                                 │ │
│  │      │    // Fallback: send tokens to operator                                   │ │
│  │      │    emit AuctionSkipped(...)                                               │ │
│  │      │  }                                                                         │ │
│  │                                                                                   │ │
│  │   4. Register in ServiceRegistry                                                  │ │
│  │                                                                                   │ │
│  └────────────────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────────────┘
                                           │
           ┌───────────────────────────────┼───────────────────────────────┐
           │                               │                               │
           ▼                               ▼                               ▼
   ┌───────────────┐              ┌───────────────┐              ┌───────────────┐
   │ RevenueToken  │              │RevenueSplitter│              │  CCA Auction  │
   │    (ERC20)    │              │               │              │  (optional)   │
   └───────────────┘              └───────────────┘              └───────────────┘


╔═══════════════════════════════════════════════════════════════════════════════════════════╗
║                              2. CCA AUCTION FLOW (If Activated)                            ║
╚═══════════════════════════════════════════════════════════════════════════════════════════╝

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              Uniswap Infrastructure (Base)                               │
│                                                                                          │
│   ServiceLauncher                                                                        │
│        │                                                                                 │
│        │ distributeToken(token, Distribution, salt)                                     │
│        ▼                                                                                 │
│   ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│   │  LiquidityLauncher                                                               │   │
│   │  • Entry point for token distributions                                           │   │
│   │  • Pulls tokens from caller                                                      │   │
│   │  • Deploys strategy via factory                                                  │   │
│   └─────────────────────────────────────────────────────────────────────────────────┘   │
│        │                                                                                 │
│        │ initializeDistribution(token, amount, configData)                              │
│        ▼                                                                                 │
│   ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│   │  FullRangeLBPStrategyFactory                                                     │   │
│   │  • Validates configData: (MigratorParameters, bytes auctionParams)              │   │
│   │  • Deploys LBPStrategy instance                                                  │   │
│   └─────────────────────────────────────────────────────────────────────────────────┘   │
│        │                                                                                 │
│        │ Creates auction via initializerFactory                                         │
│        ▼                                                                                 │
│   ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│   │  CCA Factory                                                                     │   │
│   │  • Deploys ContinuousClearingAuction contract                                    │   │
│   │  • Receives tokens for sale                                                      │   │
│   │  • Configures auction parameters (steps, floor price, duration)                  │   │
│   └─────────────────────────────────────────────────────────────────────────────────┘   │
│        │                                                                                 │
│        ▼                                                                                 │
│   ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│   │  ContinuousClearingAuction                                                       │   │
│   │  ┌─────────────────────────────────────────────────────────────────────────┐    │   │
│   │  │  DURING AUCTION (blocks: startBlock → endBlock)                         │    │   │
│   │  │  • Bidders submit bids with (budget, maxPrice)                          │    │   │
│   │  │  • Each block clears at uniform price                                   │    │   │
│   │  │  • Tokens released gradually per auctionSteps schedule                  │    │   │
│   │  └─────────────────────────────────────────────────────────────────────────┘    │   │
│   │                              │                                                   │   │
│   │                              │ After endBlock                                    │   │
│   │                              ▼                                                   │   │
│   │  ┌─────────────────────────────────────────────────────────────────────────┐    │   │
│   │  │  AFTER AUCTION                                                          │    │   │
│   │  │  • Sold tokens + raised ETH/USDC → Uniswap v4 LP                       │    │   │
│   │  │  • Unsold tokens → tokensRecipient (operator)                          │    │   │
│   │  │  • Excess funds → fundsRecipient (operator)                            │    │   │
│   │  │  • LP NFT → positionRecipient (operator)                               │    │   │
│   │  └─────────────────────────────────────────────────────────────────────────┘    │   │
│   └─────────────────────────────────────────────────────────────────────────────────┘   │
│        │                                                                                 │
│        │ migrate() after migrationBlock                                                 │
│        ▼                                                                                 │
│   ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│   │  PoolManager (Uniswap v4)                                                        │   │
│   │  • Creates TOKEN/ETH or TOKEN/USDC pool                                          │   │
│   │  • Seeds liquidity at auction clearing price                                     │   │
│   └─────────────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────────────┘


╔═══════════════════════════════════════════════════════════════════════════════════════════╗
║                              3. x402 PAYMENT & REVENUE FLOW                                ║
╚═══════════════════════════════════════════════════════════════════════════════════════════╝

┌──────────────┐          ┌──────────────┐          ┌──────────────────────────────────────┐
│   API User   │──────────│  x402 Proxy  │──────────│         x402 Service API             │
│              │  HTTP    │   (gateway)  │  HTTP    │   (endpoint from RevenueToken)       │
│              │  402     │              │  200     │                                      │
└──────────────┘          └──────┬───────┘          └──────────────────────────────────────┘
                                 │
                                 │ USDC payment
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              RevenueSplitter Contract                                    │
│                                                                                          │
│   Receives: USDC from x402 payments                                                     │
│                                                                                          │
│   split() function (callable by anyone):                                                │
│   ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│   │                                                                                 │   │
│   │   Total USDC Balance                                                            │   │
│   │         │                                                                       │   │
│   │         ├──────────────────────┐                                                │   │
│   │         │                      │                                                │   │
│   │         ▼                      ▼                                                │   │
│   │  ┌─────────────┐      ┌─────────────────────┐                                  │   │
│   │  │  Operator   │      │   Token Holders     │                                  │   │
│   │  │  (X% BPS)   │      │   (100-X% BPS)      │                                  │   │
│   │  │             │      │                     │                                  │   │
│   │  │  Direct     │      │  via depositRevenue │                                  │   │
│   │  │  transfer   │      │  to RevenueToken    │                                  │   │
│   │  └─────────────┘      └─────────────────────┘                                  │   │
│   │                                                                                 │   │
│   └─────────────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────────────┘
                                                        │
                                                        │ depositRevenue(amount)
                                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              RevenueToken Contract (ERC20)                               │
│                                                                                          │
│   Revenue Distribution (Dividend-style):                                                │
│                                                                                          │
│   revenuePerToken += (depositAmount × MAGNITUDE) / totalSupply                          │
│                                                                                          │
│   For each holder:                                                                       │
│   ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│   │  pendingRevenue = (balance × revenuePerToken / MAGNITUDE) - claimed             │   │
│   └─────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                          │
│   claim() → transfers pending USDC to holder                                            │
│                                                                                          │
│   On transfer: corrections updated so new owner doesn't claim old revenue               │
│                                                                                          │
└─────────────────────────────────────────────────────────────────────────────────────────┘
                                           │
           ┌───────────────────────────────┼───────────────────────────────┐
           │                               │                               │
           ▼                               ▼                               ▼
   ┌───────────────┐              ┌───────────────┐              ┌───────────────┐
   │  Holder A     │              │   Holder B    │              │   Operator    │
   │  (10% supply) │              │  (30% supply) │              │  (60% supply) │
   │               │              │               │              │               │
   │  claim() →    │              │  claim() →    │              │  claim() →    │
   │  10% revenue  │              │  30% revenue  │              │  60% revenue  │
   └───────────────┘              └───────────────┘              └───────────────┘
```

## Contracts

| Contract | Description |
|----------|-------------|
| `ServiceLauncher.sol` | One-click deployment of tokenized services with optional CCA auction |
| `RevenueToken.sol` | ERC-20 token with built-in dividend distribution |
| `RevenueSplitter.sol` | Receives x402 payments and splits between operator and token holders |
| `AuctionStepsEncoder.sol` | Library for encoding CCA auction release schedules |
| `ServiceRegistry.sol` | On-chain registry for service discovery |

## Token Distribution

When launching a service, the operator specifies `operatorShareBps` (basis points):

| Scenario | Operator Share | Auction Share | Result |
|----------|---------------|---------------|--------|
| CCA Success | 20% (2000 bps) | 80% | Operator gets 20%, auction sells 80% |
| CCA Fallback | 20% (2000 bps) | 80% | Operator gets 100% (fallback on CCA failure) |
| No Auction | 100% (10000 bps) | 0% | Operator gets 100%, no auction created |

## Auction Release Schedules

```
  LINEAR RELEASE                                  ACCELERATING RELEASE
  (AuctionStepsEncoder.linearRelease)             (AuctionStepsEncoder.acceleratingRelease)

  100% ┤                                          100% ┤                          ▄▄▄▄
       │                              ▄▄▄▄▄▄▄▄▄▄      │                       ▄▄▄▀
       │                         ▄▄▄▄▀                │                    ▄▄▀
   50% ┤                    ▄▄▄▄▀                 50% ┤              ▄▄▄▄▄▀
       │               ▄▄▄▄▀                          │         ▄▄▄▄▀
       │          ▄▄▄▄▀                               │    ▄▄▄▀▀
       │     ▄▄▄▄▀                                    │ ▄▄▀
    0% ┼────────────────────────────────►         0% ┼────────────────────────────────►
       Start                         End             Start                         End

  • Constant rate per block                       • 3 phases: 10% → 30% → 60%
  • Fair for all participants                     • Rewards early participants
```

## Deployment

### Prerequisites

- [Foundry](https://getfoundry.sh/)
- Base mainnet RPC URL
- Private key with ETH for gas

### Deploy

```bash
# Install dependencies
forge install

# Run tests
forge test

# Deploy to Base mainnet
source .env
forge script script/DeployServiceLauncher.s.sol --rpc-url $BASE_RPC_URL --broadcast --verify
```

### Environment Variables

```bash
PRIVATE_KEY=0x...
BASE_RPC_URL=https://mainnet.base.org
```

## Contract Addresses (Base Mainnet)

| Contract | Address |
|----------|---------|
| LiquidityLauncher | `0x00000008412db3394C91A5CbD01635c6d140637C` |
| FullRangeLBPStrategyFactory | `0x39E5eB34dD2c8082Ee1e556351ae660F33B04252` |
| CCA Factory | `0xCCccCcCAE7503Cac057829BF2811De42E16e0bD5` |
| PoolManager (v4) | `0x498581fF718922c3f8e6A244956aF099B2652b2b` |
| ServiceRegistry | `0x221afa2dC521eebF0044Ea3bcA5c58dd57F40e7C` |
| USDC | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |

## Usage Example

```solidity
LaunchParams memory params = LaunchParams({
    name: "My AI Service",
    symbol: "MYAI",
    totalSupply: 1_000_000 ether,
    operatorShareBps: 2000,  // 20% to operator
    endpoint: "https://api.myservice.com",
    category: "ai",
    salt: bytes32(uint256(1)),
    auctionEndBlock: uint64(block.number + 50000),
    auctionCurrency: address(0),  // ETH
    tickSpacing: 100,
    floorPrice: 1e18,
    minRaise: 10 ether,
    auctionSteps: AuctionStepsEncoder.linearRelease(50000)
});

(address token, address splitter, address auction) = launcher.launch(params);
```

## CCA Integration Notes

The ServiceLauncher integrates with Uniswap's [Continuous Clearing Auction](https://docs.uniswap.org/contracts/liquidity-launchpad/CCA) system. If CCA creation fails (e.g., due to authorization requirements), the contract gracefully falls back to sending all tokens to the operator.

### Config Data Format

The LBPStrategyFactory expects `configData` encoded as:

```solidity
bytes memory configData = abi.encode(
    MigratorParameters,      // LBP migration config
    abi.encode(AuctionParameters)  // Nested CCA config
);
```

## Testing

```bash
# Unit tests
forge test --match-contract "ServiceLauncherTest|AuctionStepsEncoderTest" -vv

# Fork tests (requires RPC)
forge test --match-contract ServiceLauncherForkTest --fork-url $BASE_RPC_URL -vvv
```

## Security Considerations

- **Reentrancy Protection**: All state changes happen before external calls
- **Overflow Protection**: Uses Solidity 0.8+ built-in checks
- **Graceful Degradation**: CCA failures don't break token launches
- **Access Control**: Only operators can sweep unclaimed funds after auction

## License

MIT

## Links

- [x402 Protocol](https://x402.org)
- [Uniswap CCA Docs](https://docs.uniswap.org/contracts/liquidity-launchpad/CCA)
- [Uniswap v4 Docs](https://docs.uniswap.org/contracts/v4/overview)
