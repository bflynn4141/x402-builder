/**
 * Discovery Document Generator
 *
 * Generates the .well-known/x402 discovery document that allows
 * clients to auto-detect x402 pricing.
 */

import type { ServiceConfig } from '../wizard/create.js';

/**
 * Generate x402 discovery document
 */
export function generateDiscovery(config: ServiceConfig): string {
  const discovery = {
    version: 2,
    name: config.name,
    description: config.description,
    endpoints: [
      {
        path: config.endpoint,
        method: config.method,
        pricing: {
          // Use environment variable placeholder
          amount: '{{X402_PRICE}}',
          token: config.pricing.token,
          network: config.pricing.network,
          receiver: '{{X402_RECEIVER}}',
        },
        description: getEndpointDescription(config),
      },
    ],
    contact: {
      // Users can customize this
      website: 'https://example.com',
    },
  };

  // Note: This is a static file. The actual discovery is served dynamically
  // from the worker with real env values. This file is just a template/backup.
  return JSON.stringify(discovery, null, 2);
}

function getEndpointDescription(config: ServiceConfig): string {
  switch (config.type) {
    case 'ai-inference':
      return 'AI inference endpoint - send prompts, receive completions';
    case 'data-api':
      return 'Data API - fetch premium datasets and analytics';
    case 'proxy':
      return 'API proxy - payment-gated access to upstream services';
    default:
      return config.description;
  }
}
