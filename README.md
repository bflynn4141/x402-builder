# x402-builder

**Build, deploy, and tokenize x402-powered APIs.**

Turn your API into a revenue-generating business with per-request payments and optional token-based ownership.

## Why x402?

Traditional API monetization sucks:
- **Subscriptions** → Users pay for capacity they don't use
- **API keys** → Friction, abuse, billing headaches
- **Freemium** → You subsidize heavy users

**x402 fixes this** with pay-per-request using cryptocurrency:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Traditional API Business                      │
├─────────────────────────────────────────────────────────────────┤
│  Revenue = Subscriptions + Enterprise Deals + VC Money          │
│  Problems: High churn, pricing guesswork, cash flow gaps        │
└─────────────────────────────────────────────────────────────────┘

                              vs.

┌─────────────────────────────────────────────────────────────────┐
│                      x402 API Business                           │
├─────────────────────────────────────────────────────────────────┤
│  Revenue = Price × Requests (instant, per-call)                 │
│  Benefits: No churn, usage-based pricing, instant settlement    │
└─────────────────────────────────────────────────────────────────┘
```

## Why Tokenize?

x402 gets you paid. **Tokenization** lets you:

| Benefit | Description |
|---------|-------------|
| **Raise Capital** | Sell tokens via auction to fund development |
| **Share Revenue** | Token holders automatically earn from API usage |
| **Align Incentives** | Users who hold tokens want your API to succeed |
| **Bootstrap Liquidity** | Auto-seed Uniswap v4 pool after token sale |
| **Decentralize Ownership** | Transition from founder-owned to community-owned |

### Revenue Flow

```
┌──────────────┐          ┌──────────────┐          ┌──────────────┐
│   API User   │──────────│  x402 Proxy  │──────────│  Your API    │
│              │  $0.001  │              │  Request │              │
└──────────────┘  /call   └──────┬───────┘          └──────────────┘
                                 │
                                 │ USDC payment
                                 ▼
                    ┌────────────────────────┐
                    │    RevenueSplitter     │
                    │                        │
                    │  ┌──────────────────┐  │
                    │  │ 20% → Operator   │  │
                    │  │ 80% → Holders    │  │
                    │  └──────────────────┘  │
                    └────────────────────────┘
                                 │
           ┌─────────────────────┼─────────────────────┐
           │                     │                     │
           ▼                     ▼                     ▼
    ┌─────────────┐       ┌─────────────┐       ┌─────────────┐
    │  Holder A   │       │  Holder B   │       │  Operator   │
    │  10% tokens │       │  30% tokens │       │  60% tokens │
    │             │       │             │       │             │
    │  Earns 8%   │       │  Earns 24%  │       │  Earns 68%  │
    │  of revenue │       │  of revenue │       │  of revenue │
    └─────────────┘       └─────────────┘       └─────────────┘
```

## Quick Start

### 1. Create an x402 API

```bash
npx x402-builder create

# Or with flags
npx x402-builder create \
  --name my-ai-api \
  --type ai-inference \
  --price 0.001 \
  --wallet 0x...
```

### 2. Deploy to Cloudflare

```bash
npx x402-builder deploy
```

### 3. Tokenize (Optional)

```bash
npx x402-builder tokenize \
  --name "My AI Service" \
  --symbol "MYAI" \
  --supply 1000000 \
  --operator-share 20 \
  --auction-duration 7d
```

This deploys:
- **RevenueToken** - ERC-20 with built-in dividends
- **RevenueSplitter** - Routes payments to token holders
- **CCA Auction** - Fair price discovery via Uniswap

## Architecture

```
╔═══════════════════════════════════════════════════════════════════════════════════════════╗
║                           x402 SERVICE TOKENIZATION ARCHITECTURE                           ║
╚═══════════════════════════════════════════════════════════════════════════════════════════╝

                                    ┌──────────────┐
                                    │   Operator   │
                                    │  (You)       │
                                    └──────┬───────┘
                                           │
                                           │ tokenize()
                                           ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              ServiceLauncher Contract                                    │
│                                                                                          │
│   1. Deploy RevenueToken ─────────────────────────────┐                                 │
│      • ERC-20 with dividend tracking                  │                                 │
│      • Operator gets X% immediately                   │                                 │
│                                                       ▼                                 │
│   2. Deploy RevenueSplitter ◄────────────────── links to token                          │
│      • Receives x402 USDC payments                                                      │
│      • Splits to operator + holders                                                     │
│                                                                                          │
│   3. Create CCA Auction (optional) ──────────────────────────────────────┐              │
│      • Tokens released over time                                         │              │
│      • Bidders compete for best price                                    │              │
│      • Auto-seeds Uniswap v4 pool                                        │              │
│                                                                          ▼              │
│   4. Register in ServiceRegistry ◄───────────────────────────── for discovery           │
│                                                                                          │
└─────────────────────────────────────────────────────────────────────────────────────────┘
                                           │
           ┌───────────────────────────────┼───────────────────────────────┐
           │                               │                               │
           ▼                               ▼                               ▼
   ┌───────────────┐              ┌───────────────┐              ┌───────────────┐
   │ RevenueToken  │              │RevenueSplitter│              │  CCA Auction  │
   │    (ERC20)    │              │  (payments)   │              │  (optional)   │
   │               │              │               │              │               │
   │ • Dividends   │              │ • Split %     │              │ • Fair price  │
   │ • Transfers   │              │ • Auto-claim  │              │ • Liquidity   │
   └───────────────┘              └───────────────┘              └───────────────┘


╔═══════════════════════════════════════════════════════════════════════════════════════════╗
║                              TOKEN LAUNCH OPTIONS                                          ║
╚═══════════════════════════════════════════════════════════════════════════════════════════╝

  OPTION A: No Auction (100% to Operator)         OPTION B: CCA Auction (Fair Launch)
  ───────────────────────────────────────         ─────────────────────────────────────

  Total Supply: 1,000,000 tokens                  Total Supply: 1,000,000 tokens
  operatorShare: 100%                             operatorShare: 20%

  ┌────────────────────────────────┐              ┌────────────────────────────────┐
  │  Operator: 1,000,000 (100%)    │              │  Operator:   200,000 (20%)     │
  │                                │              │  Auction:    800,000 (80%)     │
  │  You control distribution      │              │    ├─ Sold → Uniswap LP        │
  │  Sell OTC, airdrop, vest, etc. │              │    └─ Unsold → Operator        │
  └────────────────────────────────┘              └────────────────────────────────┘

  Best for:                                       Best for:
  • Private fundraising                           • Public launches
  • Team/investor allocations                     • Community distribution
  • Gradual rollout                               • Price discovery


╔═══════════════════════════════════════════════════════════════════════════════════════════╗
║                              CCA AUCTION MECHANICS                                         ║
╚═══════════════════════════════════════════════════════════════════════════════════════════╝

  How Continuous Clearing Auction Works:

  ┌─────────────────────────────────────────────────────────────────────────────────────────┐
  │                                                                                         │
  │   Block 1    Block 2    Block 3    Block 4    Block 5   ...   Block N                  │
  │      │          │          │          │          │              │                       │
  │      ▼          ▼          ▼          ▼          ▼              ▼                       │
  │   ┌─────┐   ┌─────┐   ┌─────┐   ┌─────┐   ┌─────┐         ┌─────┐                     │
  │   │ 2%  │   │ 2%  │   │ 2%  │   │ 2%  │   │ 2%  │  ...    │ 2%  │  Tokens released    │
  │   └─────┘   └─────┘   └─────┘   └─────┘   └─────┘         └─────┘  per block          │
  │                                                                                         │
  │   Bidders submit: (budget, maxPrice)                                                   │
  │   Each block clears at uniform price where supply = demand                             │
  │   No front-running, no gas wars, fair for everyone                                     │
  │                                                                                         │
  └─────────────────────────────────────────────────────────────────────────────────────────┘

  After Auction Ends:

  ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
  │  Sold Tokens    │     │  Raised ETH     │     │  Unsold Tokens  │
  │       +         │ ──► │       =         │ ──► │       ↓         │
  │  Raised ETH     │     │  Uniswap v4 LP  │     │    Operator     │
  └─────────────────┘     └─────────────────┘     └─────────────────┘

  • Trading starts immediately at auction clearing price
  • Operator receives LP position NFT
  • No manual pool creation needed
```

## Smart Contracts

| Contract | Description | Source |
|----------|-------------|--------|
| `ServiceLauncher` | One-click tokenization with CCA integration | [View](packages/contracts/src/ServiceLauncher.sol) |
| `RevenueToken` | ERC-20 with automatic dividend distribution | [View](packages/contracts/src/RevenueToken.sol) |
| `RevenueSplitter` | Splits x402 payments to operator + holders | [View](packages/contracts/src/RevenueSplitter.sol) |
| `AuctionStepsEncoder` | Library for CCA release schedules | [View](packages/contracts/src/AuctionStepsEncoder.sol) |
| `ServiceRegistry` | On-chain service discovery | [View](packages/contracts/src/ServiceRegistry.sol) |

## Contract Addresses (Base Mainnet)

| Contract | Address |
|----------|---------|
| LiquidityLauncher | `0x00000008412db3394C91A5CbD01635c6d140637C` |
| LBPStrategyFactory | `0x39E5eB34dD2c8082Ee1e556351ae660F33B04252` |
| CCA Factory | `0xCCccCcCAE7503Cac057829BF2811De42E16e0bD5` |
| PoolManager (v4) | `0x498581fF718922c3f8e6A244956aF099B2652b2b` |
| ServiceRegistry | `0x221afa2dC521eebF0044Ea3bcA5c58dd57F40e7C` |
| USDC | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |

## Service Types

| Type | Description | Default Price |
|------|-------------|---------------|
| `ai-inference` | Wrap an LLM or ML model | $0.001/req |
| `data-api` | Serve datasets or analytics | $0.0001/req |
| `proxy` | Add payments to existing APIs | $0.0005/req |
| `custom` | Build something unique | $0.001/req |

## Payment Flow

```
Client                          Your API                    Blockchain
  │                                │                            │
  │──── GET /api/data ───────────►│                            │
  │                                │                            │
  │◄─── 402 Payment Required ─────│                            │
  │     (price: $0.001 USDC)       │                            │
  │                                │                            │
  │──── [Sign USDC payment] ──────────────────────────────────►│
  │                                │                            │
  │──── GET /api/data ───────────►│                            │
  │     X-Payment: <signature>     │                            │
  │                                │──── Verify payment ───────►│
  │                                │◄─── Valid ─────────────────│
  │◄─── 200 OK + data ────────────│                            │
  │                                │                            │
  │                                │     [Later: split() called]│
  │                                │     Revenue → Token Holders│
```

## Development

### Prerequisites

- Node.js 18+
- [Foundry](https://getfoundry.sh/) (for contracts)
- Cloudflare account (for deployment)

### Install

```bash
git clone https://github.com/bflynn4141/x402-builder.git
cd x402-builder
npm install
```

### Test Contracts

```bash
cd packages/contracts
forge install
forge test
```

### Test with Fork

```bash
forge test --match-contract ServiceLauncherForkTest --fork-url https://mainnet.base.org -vvv
```

## Configuration

### x402 Settings (wrangler.toml)

```toml
[vars]
X402_PRICE = "0.001"        # Price per request in USD
X402_TOKEN = "USDC"         # Payment token
X402_NETWORK = "base"       # Network (base, ethereum, arbitrum)
X402_RECEIVER = "0x..."     # Your wallet or RevenueSplitter address
```

### Tokenization Settings

```typescript
const params = {
  name: "My AI Service",
  symbol: "MYAI",
  totalSupply: 1_000_000,      // 1M tokens
  operatorShareBps: 2000,       // 20% to operator
  endpoint: "https://api.example.com",
  category: "ai",
  auctionEndBlock: currentBlock + 50000,  // ~7 days on Base
  auctionCurrency: "0x0000...0000",        // ETH (or USDC address)
  floorPrice: 1e18,             // 1 token = 1 ETH minimum
  minRaise: 10e18,              // 10 ETH graduation threshold
};
```

## Example: Tokenize an AI API

```solidity
// 1. Deploy via ServiceLauncher
LaunchParams memory params = LaunchParams({
    name: "GPT-5 Proxy",
    symbol: "GPT5",
    totalSupply: 1_000_000 ether,
    operatorShareBps: 2000,           // Keep 20%
    endpoint: "https://gpt5.x402.io",
    category: "ai",
    salt: bytes32(uint256(1)),
    auctionEndBlock: uint64(block.number + 50000),
    auctionCurrency: address(0),      // Raise in ETH
    tickSpacing: 100,
    floorPrice: 1e15,                 // $1 floor at $1000 ETH
    minRaise: 100 ether,              // Need 100 ETH to graduate
    auctionSteps: AuctionStepsEncoder.linearRelease(50000)
});

(address token, address splitter, address auction) = launcher.launch(params);

// 2. Update your x402 API to send payments to `splitter`
// 3. Token holders automatically earn from every API call
```

## Integrations

- **[Uniswap v4](https://docs.uniswap.org/contracts/v4/overview)** - Liquidity pools
- **[Uniswap CCA](https://docs.uniswap.org/contracts/liquidity-launchpad/CCA)** - Fair token auctions
- **[x402 Protocol](https://x402.org)** - HTTP payment standard
- **[Cloudflare Workers](https://workers.cloudflare.com)** - Edge deployment

## License

MIT

---

**Built for the x402 ecosystem** | [x402.org](https://x402.org) | [Docs](https://docs.x402.org)
