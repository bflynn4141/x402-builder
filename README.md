# x402-builder

Build and deploy x402-powered APIs in minutes.

## What is x402?

[x402](https://x402.org) is a protocol for HTTP micropayments using the 402 "Payment Required" status code. It lets you monetize APIs by charging cryptocurrency per-request.

## Quick Start

```bash
# Create a new x402 service interactively
npx x402-builder create

# Or with flags
npx x402-builder create \
  --name my-ai-api \
  --type ai-inference \
  --price 0.001 \
  --wallet 0x...
```

## Service Types

| Type | Description | Default Price |
|------|-------------|---------------|
| `ai-inference` | Wrap an LLM or ML model | $0.001/req |
| `data-api` | Serve datasets or analytics | $0.0001/req |
| `proxy` | Add payments to existing APIs | $0.0005/req |
| `custom` | Build something unique | $0.001/req |

## How It Works

1. **Create** - The wizard guides you through service design and pricing
2. **Customize** - Edit `src/handler.ts` with your business logic
3. **Deploy** - One-click deploy to Cloudflare Workers
4. **Get Paid** - Users pay per-request using x402-compatible wallets

## Generated Project Structure

```
my-api/
├── src/
│   ├── index.ts      # Worker entry point
│   ├── x402.ts       # Payment verification middleware
│   └── handler.ts    # Your business logic (edit this!)
├── .well-known/
│   └── x402          # Discovery document
├── wrangler.toml     # Cloudflare config
└── package.json
```

## Commands

```bash
# Create new project
npx x402-builder create

# Deploy to Cloudflare
npx x402-builder deploy

# Validate configuration
npx x402-builder validate

# Run local dev server
npx x402-builder dev  # Coming soon
```

## Configuration

All x402 settings are in `wrangler.toml`:

```toml
[vars]
X402_PRICE = "0.001"        # Price per request in USD
X402_TOKEN = "USDC"         # Payment token
X402_NETWORK = "base"       # Network (base or ethereum)
X402_RECEIVER = "0x..."     # Your wallet address
```

## Making Requests

Clients need an x402-compatible wallet:

```bash
# Using Clara wallet
clara> wallet_pay_x402 url="https://my-api.workers.dev/api/generate"

# Using any x402 client
curl -X POST https://my-api.workers.dev/api/generate \
  -H "X-Payment: <base64-encoded-payment>"
```

## Payment Flow

```
Client                          Your API
  │                                │
  │──── GET /api/data ───────────►│
  │                                │
  │◄─── 402 Payment Required ─────│
  │     (includes price + wallet)  │
  │                                │
  │──── [Sign payment] ──────────►│
  │                                │
  │──── GET /api/data ───────────►│
  │     X-Payment: <signature>     │
  │                                │
  │◄─── 200 OK + data ────────────│
  │                                │
```

## License

MIT

---

Built with ❤️ for the x402 ecosystem
