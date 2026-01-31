/**
 * x402 Middleware Generator
 *
 * Generates the server-side x402 payment verification middleware.
 */

import type { ServiceConfig } from '../wizard/create.js';

/**
 * Generate the x402 middleware code
 */
export function generateMiddleware(config: ServiceConfig): string {
  return `/**
 * x402 Server Middleware
 *
 * Handles payment verification for x402-powered APIs.
 *
 * Flow:
 * 1. Check for X-Payment header
 * 2. If missing, return 402 with payment requirements
 * 3. If present, verify the payment signature
 * 4. If valid, allow request to proceed
 *
 * @see https://x402.org for protocol specification
 */

import { verifyTypedData, type Hex } from 'viem';

export interface X402Config {
  priceUsd: number;
  token: 'USDC';
  network: 'base' | 'ethereum';
  receiver: string;
}

// Token addresses by network
const TOKEN_ADDRESSES: Record<string, Record<string, Hex>> = {
  base: {
    USDC: '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913',
  },
  ethereum: {
    USDC: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
  },
};

// Chain IDs
const CHAIN_IDS: Record<string, number> = {
  base: 8453,
  ethereum: 1,
};

/**
 * x402 middleware
 *
 * Returns a Response if payment is required (402).
 * Returns null if payment is valid and request should proceed.
 */
export async function x402Middleware(
  request: Request,
  config: X402Config
): Promise<Response | null> {
  // Check for payment header
  const paymentHeader = request.headers.get('X-Payment');

  if (!paymentHeader) {
    // No payment - return 402 with requirements
    return createPaymentRequired(config, request);
  }

  // Parse and verify payment
  try {
    const payment = JSON.parse(
      Buffer.from(paymentHeader, 'base64').toString('utf-8')
    ) as PaymentPayload;

    const isValid = await verifyPayment(payment, config);

    if (!isValid) {
      return new Response(
        JSON.stringify({ error: 'Invalid payment signature' }),
        {
          status: 402,
          headers: { 'Content-Type': 'application/json' },
        }
      );
    }

    // Payment valid! Request can proceed
    // In production, you'd also execute the on-chain settlement here
    console.log(\`[x402] Payment verified from \${payment.authorization.from}\`);

    return null;

  } catch (error) {
    console.error('[x402] Payment verification error:', error);
    return new Response(
      JSON.stringify({ error: 'Payment verification failed' }),
      {
        status: 402,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  }
}

/**
 * Create 402 Payment Required response
 */
function createPaymentRequired(config: X402Config, request: Request): Response {
  const tokenAddress = TOKEN_ADDRESSES[config.network]?.[config.token];
  if (!tokenAddress) {
    throw new Error(\`Unknown token: \${config.token} on \${config.network}\`);
  }

  // Convert USD price to token base units (USDC has 6 decimals)
  const amountBaseUnits = Math.ceil(config.priceUsd * 1_000_000).toString();

  // Generate a unique nonce for this request
  const nonce = generateNonce();

  // Build x402 v2 payment requirements
  const requirements = {
    version: 2,
    network: \`eip155:\${CHAIN_IDS[config.network]}\`,
    token: tokenAddress,
    amount: amountBaseUnits,
    receiver: config.receiver,
    // EIP-3009 authorization fields
    validAfter: '0',
    validBefore: Math.floor(Date.now() / 1000 + 3600).toString(), // 1 hour
    nonce,
  };

  // Return 402 with payment details
  return new Response(
    JSON.stringify({
      error: 'Payment required',
      x402: requirements,
    }),
    {
      status: 402,
      headers: {
        'Content-Type': 'application/json',
        'X-Payment-Required': Buffer.from(JSON.stringify(requirements)).toString('base64'),
        // Also include human-readable header
        'X-Payment-Amount': \`\${config.priceUsd} USD\`,
        'X-Payment-Token': \`\${config.token} on \${config.network}\`,
      },
    }
  );
}

/**
 * Payment payload structure (from client)
 */
interface PaymentPayload {
  authorization: {
    from: Hex;
    to: Hex;
    value: string;
    validAfter: string;
    validBefore: string;
    nonce: string;
  };
  signature: Hex;
}

/**
 * Verify payment signature
 *
 * This verifies the EIP-712 typed data signature for EIP-3009 authorization.
 */
async function verifyPayment(
  payment: PaymentPayload,
  config: X402Config
): Promise<boolean> {
  const tokenAddress = TOKEN_ADDRESSES[config.network]?.[config.token];
  const chainId = CHAIN_IDS[config.network];

  if (!tokenAddress || !chainId) {
    return false;
  }

  // Verify basic requirements
  const { authorization, signature } = payment;

  // Check receiver matches
  if (authorization.to.toLowerCase() !== config.receiver.toLowerCase()) {
    console.error('[x402] Receiver mismatch');
    return false;
  }

  // Check amount is sufficient
  const expectedAmount = Math.ceil(config.priceUsd * 1_000_000);
  if (BigInt(authorization.value) < BigInt(expectedAmount)) {
    console.error('[x402] Insufficient payment amount');
    return false;
  }

  // Check validity window
  const now = Math.floor(Date.now() / 1000);
  if (BigInt(authorization.validAfter) > BigInt(now)) {
    console.error('[x402] Payment not yet valid');
    return false;
  }
  if (BigInt(authorization.validBefore) < BigInt(now)) {
    console.error('[x402] Payment expired');
    return false;
  }

  // Verify EIP-712 signature
  // EIP-3009 TransferWithAuthorization typed data
  const domain = {
    name: config.token,
    version: '2',
    chainId: BigInt(chainId),
    verifyingContract: tokenAddress,
  };

  const types = {
    TransferWithAuthorization: [
      { name: 'from', type: 'address' },
      { name: 'to', type: 'address' },
      { name: 'value', type: 'uint256' },
      { name: 'validAfter', type: 'uint256' },
      { name: 'validBefore', type: 'uint256' },
      { name: 'nonce', type: 'bytes32' },
    ],
  };

  const message = {
    from: authorization.from,
    to: authorization.to,
    value: BigInt(authorization.value),
    validAfter: BigInt(authorization.validAfter),
    validBefore: BigInt(authorization.validBefore),
    nonce: authorization.nonce as Hex,
  };

  try {
    const recoveredAddress = await verifyTypedData({
      address: authorization.from,
      domain,
      types,
      primaryType: 'TransferWithAuthorization',
      message,
      signature,
    });

    return recoveredAddress;
  } catch (error) {
    console.error('[x402] Signature verification failed:', error);
    return false;
  }
}

/**
 * Generate a random nonce (bytes32)
 */
function generateNonce(): Hex {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return ('0x' + Array.from(bytes).map(b => b.toString(16).padStart(2, '0')).join('')) as Hex;
}
`;
}
