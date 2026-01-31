/**
 * Validate Wizard
 *
 * Validates x402 project configuration.
 */

import { readFile, stat } from 'fs/promises';
import { join } from 'path';
import chalk from 'chalk';

export interface ValidateOptions {
  dir?: string;
}

interface ValidationResult {
  valid: boolean;
  errors: string[];
  warnings: string[];
}

/**
 * Validate an x402 project
 */
export async function validateProject(options: ValidateOptions): Promise<void> {
  const projectDir = options.dir || process.cwd();
  const result: ValidationResult = {
    valid: true,
    errors: [],
    warnings: [],
  };

  console.log(chalk.bold('\n🔍 Validating x402 project...\n'));

  // Check required files
  const requiredFiles = [
    'wrangler.toml',
    'package.json',
    'src/index.ts',
    'src/x402.ts',
    'src/handler.ts',
  ];

  for (const file of requiredFiles) {
    try {
      await stat(join(projectDir, file));
      console.log(chalk.green(`  ✓ ${file}`));
    } catch {
      result.valid = false;
      result.errors.push(`Missing required file: ${file}`);
      console.log(chalk.red(`  ✗ ${file}`));
    }
  }

  // Check wrangler.toml configuration
  try {
    const wranglerContent = await readFile(
      join(projectDir, 'wrangler.toml'),
      'utf-8'
    );

    const requiredVars = ['X402_PRICE', 'X402_TOKEN', 'X402_NETWORK', 'X402_RECEIVER'];

    for (const varName of requiredVars) {
      if (!wranglerContent.includes(varName)) {
        result.warnings.push(`Missing variable in wrangler.toml: ${varName}`);
        console.log(chalk.yellow(`  ⚠ Missing var: ${varName}`));
      }
    }

    // Validate wallet address format
    const receiverMatch = wranglerContent.match(/X402_RECEIVER\s*=\s*["']?(0x[a-fA-F0-9]{40})["']?/);
    if (receiverMatch) {
      console.log(chalk.green(`  ✓ Receiver wallet: ${receiverMatch[1].slice(0, 10)}...`));
    } else {
      result.warnings.push('Could not parse X402_RECEIVER - ensure it\'s a valid 0x address');
    }

    // Validate price
    const priceMatch = wranglerContent.match(/X402_PRICE\s*=\s*["']?([0-9.]+)["']?/);
    if (priceMatch) {
      const price = parseFloat(priceMatch[1]);
      if (price > 0 && price < 100) {
        console.log(chalk.green(`  ✓ Price: $${price} per request`));
      } else {
        result.warnings.push(`Unusual price: $${price} - verify this is correct`);
      }
    }

  } catch (error) {
    // Already reported as missing file
  }

  // Summary
  console.log();

  if (result.errors.length > 0) {
    console.log(chalk.red.bold('Errors:'));
    for (const error of result.errors) {
      console.log(chalk.red(`  • ${error}`));
    }
  }

  if (result.warnings.length > 0) {
    console.log(chalk.yellow.bold('Warnings:'));
    for (const warning of result.warnings) {
      console.log(chalk.yellow(`  • ${warning}`));
    }
  }

  if (result.valid && result.warnings.length === 0) {
    console.log(chalk.green.bold('✅ Project is valid and ready to deploy!'));
  } else if (result.valid) {
    console.log(chalk.yellow.bold('⚠️ Project has warnings but can be deployed.'));
  } else {
    console.log(chalk.red.bold('❌ Project has errors. Fix them before deploying.'));
    process.exit(1);
  }
}
