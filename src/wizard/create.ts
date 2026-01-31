/**
 * Create Wizard
 *
 * Interactive wizard that guides users through creating an x402 service.
 */

import { input, select, confirm, number } from '@inquirer/prompts';
import chalk from 'chalk';
import ora from 'ora';
import { generateProject } from '../generators/project.js';
import { deployProject } from './deploy.js';

export interface CreateOptions {
  name?: string;
  type?: string;
  price?: string;
  wallet?: string;
  skipDeploy?: boolean;
}

export interface ServiceConfig {
  name: string;
  type: 'ai-inference' | 'data-api' | 'proxy' | 'custom';
  description: string;
  endpoint: string;
  method: 'GET' | 'POST';
  pricing: {
    pricePerRequest: number; // in USD
    token: 'USDC';
    network: 'base' | 'ethereum';
  };
  wallet: string;
}

/**
 * Run the create wizard
 */
export async function createWizard(options: CreateOptions): Promise<void> {
  console.log(chalk.bold('\n🚀 Let\'s build your x402-powered API!\n'));

  // Step 1: Project name
  const name = options.name || await input({
    message: 'What should we call your project?',
    default: 'my-x402-api',
    validate: (value) => {
      if (!/^[a-z0-9-]+$/.test(value)) {
        return 'Use lowercase letters, numbers, and hyphens only';
      }
      return true;
    },
  });

  // Step 2: Service type
  const type = options.type as ServiceConfig['type'] || await select({
    message: 'What kind of service are you building?',
    choices: [
      {
        value: 'ai-inference',
        name: '🤖 AI Inference API',
        description: 'Wrap an LLM or ML model with paid access',
      },
      {
        value: 'data-api',
        name: '📊 Data API',
        description: 'Serve datasets, analytics, or scraped content',
      },
      {
        value: 'proxy',
        name: '🔌 Proxy / Gateway',
        description: 'Add payments to an existing API',
      },
      {
        value: 'custom',
        name: '⚡ Custom Service',
        description: 'Build something unique',
      },
    ],
  }) as ServiceConfig['type'];

  // Step 3: Description
  const description = await input({
    message: 'Describe your service in one sentence:',
    default: getDefaultDescription(type),
  });

  // Step 4: Endpoint design
  console.log(chalk.gray('\n📐 API Design\n'));

  const endpoint = await input({
    message: 'What\'s your main endpoint path?',
    default: getDefaultEndpoint(type),
  });

  const method = await select({
    message: 'HTTP method?',
    choices: [
      { value: 'POST', name: 'POST (for sending data)' },
      { value: 'GET', name: 'GET (for fetching data)' },
    ],
    default: type === 'data-api' ? 'GET' : 'POST',
  }) as 'GET' | 'POST';

  // Step 5: Pricing
  console.log(chalk.gray('\n💰 Pricing\n'));

  const priceInput = options.price || await input({
    message: 'Price per request (in USD)?',
    default: getDefaultPrice(type),
    validate: (value) => {
      const num = parseFloat(value);
      if (isNaN(num) || num <= 0) {
        return 'Enter a valid positive number';
      }
      if (num > 100) {
        return 'That seems high! Max $100 per request.';
      }
      return true;
    },
  });

  const pricePerRequest = parseFloat(priceInput);

  // Show pricing breakdown
  console.log(chalk.gray(`
  📊 At $${pricePerRequest.toFixed(4)} per request:
     • 1,000 requests = $${(pricePerRequest * 1000).toFixed(2)}
     • 10,000 requests = $${(pricePerRequest * 10000).toFixed(2)}
     • 100,000 requests = $${(pricePerRequest * 100000).toFixed(2)}
  `));

  // Step 6: Wallet address
  const wallet = options.wallet || await input({
    message: 'Your wallet address (to receive payments):',
    validate: (value) => {
      if (!/^0x[a-fA-F0-9]{40}$/.test(value)) {
        return 'Enter a valid Ethereum address (0x...)';
      }
      return true;
    },
  });

  // Step 7: Network selection
  const network = await select({
    message: 'Which network should payments use?',
    choices: [
      {
        value: 'base',
        name: '🔵 Base (Recommended)',
        description: 'Low fees (~$0.001), fast confirmations',
      },
      {
        value: 'ethereum',
        name: '🔷 Ethereum',
        description: 'Higher fees, more liquidity',
      },
    ],
    default: 'base',
  }) as 'base' | 'ethereum';

  // Build config
  const config: ServiceConfig = {
    name,
    type,
    description,
    endpoint,
    method,
    pricing: {
      pricePerRequest,
      token: 'USDC',
      network,
    },
    wallet,
  };

  // Show summary
  console.log(chalk.bold('\n📋 Summary\n'));
  console.log(chalk.white(`  Name:        ${chalk.cyan(config.name)}`));
  console.log(chalk.white(`  Type:        ${chalk.cyan(config.type)}`));
  console.log(chalk.white(`  Endpoint:    ${chalk.cyan(`${config.method} ${config.endpoint}`)}`));
  console.log(chalk.white(`  Price:       ${chalk.green(`$${config.pricing.pricePerRequest}`)} per request`));
  console.log(chalk.white(`  Network:     ${chalk.cyan(config.pricing.network)}`));
  console.log(chalk.white(`  Wallet:      ${chalk.gray(config.wallet.slice(0, 10) + '...')}`));

  const proceed = await confirm({
    message: 'Generate project?',
    default: true,
  });

  if (!proceed) {
    console.log(chalk.yellow('\n👋 No worries! Run `x402-builder create` when you\'re ready.\n'));
    return;
  }

  // Generate the project
  const spinner = ora('Generating project...').start();

  try {
    const projectDir = await generateProject(config);
    spinner.succeed(`Project generated at ${chalk.cyan(projectDir)}`);

    // Show next steps
    console.log(chalk.bold('\n✨ Next Steps\n'));
    console.log(chalk.white(`  1. ${chalk.cyan(`cd ${name}`)}`));
    console.log(chalk.white(`  2. ${chalk.cyan('npm install')}`));
    console.log(chalk.white(`  3. Edit ${chalk.cyan('src/handler.ts')} with your logic`));
    console.log(chalk.white(`  4. ${chalk.cyan('npm run dev')} to test locally`));
    console.log(chalk.white(`  5. ${chalk.cyan('npm run deploy')} when ready!`));
    console.log();

    // Offer to deploy
    if (!options.skipDeploy) {
      const shouldDeploy = await confirm({
        message: 'Deploy to Cloudflare Workers now?',
        default: false,
      });

      if (shouldDeploy) {
        await deployProject({ dir: projectDir });
      }
    }

  } catch (error) {
    spinner.fail('Failed to generate project');
    console.error(chalk.red(error instanceof Error ? error.message : 'Unknown error'));
    process.exit(1);
  }
}

function getDefaultDescription(type: ServiceConfig['type']): string {
  switch (type) {
    case 'ai-inference':
      return 'AI-powered text generation API';
    case 'data-api':
      return 'Premium data and analytics API';
    case 'proxy':
      return 'Payment-gated API proxy';
    default:
      return 'A powerful paid API';
  }
}

function getDefaultEndpoint(type: ServiceConfig['type']): string {
  switch (type) {
    case 'ai-inference':
      return '/api/generate';
    case 'data-api':
      return '/api/data';
    case 'proxy':
      return '/api/proxy';
    default:
      return '/api';
  }
}

function getDefaultPrice(type: ServiceConfig['type']): string {
  switch (type) {
    case 'ai-inference':
      return '0.001'; // $0.001 per inference
    case 'data-api':
      return '0.0001'; // $0.0001 per data fetch
    case 'proxy':
      return '0.0005'; // $0.0005 per proxied request
    default:
      return '0.001';
  }
}
