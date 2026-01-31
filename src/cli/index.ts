#!/usr/bin/env node
/**
 * x402-builder CLI
 *
 * Build and deploy x402-powered APIs with ease.
 */

import { Command } from 'commander';
import chalk from 'chalk';
import { createWizard } from '../wizard/create.js';
import { deployProject } from '../wizard/deploy.js';
import { validateProject } from '../wizard/validate.js';

const program = new Command();

// ASCII art banner
const banner = `
${chalk.cyan('╔═══════════════════════════════════════╗')}
${chalk.cyan('║')}  ${chalk.bold.white('x402-builder')} ${chalk.gray('v0.1.0')}               ${chalk.cyan('║')}
${chalk.cyan('║')}  ${chalk.gray('Build monetized APIs in minutes')}     ${chalk.cyan('║')}
${chalk.cyan('╚═══════════════════════════════════════╝')}
`;

program
  .name('x402-builder')
  .description('Build and deploy x402-powered APIs')
  .version('0.1.0');

// Main create command - the wizard
program
  .command('create')
  .description('Create a new x402-powered API (interactive wizard)')
  .option('-n, --name <name>', 'Project name')
  .option('-t, --type <type>', 'Service type (ai-inference, data-api, proxy, custom)')
  .option('-p, --price <price>', 'Price per request in USD (e.g., 0.001)')
  .option('-w, --wallet <address>', 'Your wallet address to receive payments')
  .option('--skip-deploy', 'Skip deployment step')
  .action(async (options) => {
    console.log(banner);
    await createWizard(options);
  });

// Deploy command
program
  .command('deploy')
  .description('Deploy your x402 service to Cloudflare Workers')
  .option('-d, --dir <directory>', 'Project directory', '.')
  .action(async (options) => {
    console.log(banner);
    await deployProject(options);
  });

// Validate command
program
  .command('validate')
  .description('Validate your x402 configuration')
  .option('-d, --dir <directory>', 'Project directory', '.')
  .action(async (options) => {
    await validateProject(options);
  });

// Dev server command (future)
program
  .command('dev')
  .description('Run local development server with x402 mock payments')
  .option('-p, --port <port>', 'Port to run on', '8787')
  .action(async (options) => {
    console.log(chalk.yellow('🚧 Local dev server coming soon!'));
    console.log(chalk.gray('For now, use `wrangler dev` in your project directory.'));
  });

// Register command (future)
program
  .command('register')
  .description('Register your service with x402 discovery catalogs')
  .action(async () => {
    console.log(chalk.yellow('🚧 Discovery registration coming soon!'));
  });

// Default action - show help or run wizard
program
  .action(() => {
    console.log(banner);
    program.help();
  });

program.parse();
