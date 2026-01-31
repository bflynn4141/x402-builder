/**
 * Deploy Wizard
 *
 * Handles deployment to Cloudflare Workers.
 */

import { exec } from 'child_process';
import { promisify } from 'util';
import { stat } from 'fs/promises';
import { join } from 'path';
import chalk from 'chalk';
import ora from 'ora';
import { confirm } from '@inquirer/prompts';

const execAsync = promisify(exec);

export interface DeployOptions {
  dir?: string;
}

/**
 * Deploy project to Cloudflare Workers
 */
export async function deployProject(options: DeployOptions): Promise<void> {
  const projectDir = options.dir || process.cwd();

  // Validate project structure
  const spinner = ora('Validating project...').start();

  try {
    await stat(join(projectDir, 'wrangler.toml'));
    await stat(join(projectDir, 'package.json'));
    spinner.succeed('Project structure valid');
  } catch {
    spinner.fail('Invalid project directory');
    console.log(chalk.red('\nMissing wrangler.toml or package.json'));
    console.log(chalk.gray('Run this command from an x402 project directory.'));
    process.exit(1);
  }

  // Check for wrangler
  spinner.start('Checking Wrangler...');
  try {
    await execAsync('npx wrangler --version', { cwd: projectDir });
    spinner.succeed('Wrangler available');
  } catch {
    spinner.fail('Wrangler not found');
    console.log(chalk.yellow('\nInstalling wrangler...'));
    await execAsync('npm install wrangler', { cwd: projectDir });
  }

  // Check for Cloudflare login
  spinner.start('Checking Cloudflare authentication...');
  try {
    await execAsync('npx wrangler whoami', { cwd: projectDir });
    spinner.succeed('Authenticated with Cloudflare');
  } catch {
    spinner.warn('Not logged in to Cloudflare');
    console.log(chalk.yellow('\nRun: npx wrangler login'));

    const shouldLogin = await confirm({
      message: 'Open browser to login now?',
      default: true,
    });

    if (shouldLogin) {
      await execAsync('npx wrangler login', { cwd: projectDir });
    } else {
      console.log(chalk.gray('Run `npx wrangler login` when ready.'));
      process.exit(0);
    }
  }

  // Deploy
  console.log(chalk.bold('\n🚀 Deploying to Cloudflare Workers...\n'));

  try {
    const { stdout, stderr } = await execAsync('npx wrangler deploy', {
      cwd: projectDir,
    });

    if (stderr && !stderr.includes('Uploaded')) {
      console.log(chalk.yellow(stderr));
    }

    console.log(stdout);

    // Extract URL from output
    const urlMatch = stdout.match(/https:\/\/[^\s]+\.workers\.dev/);
    if (urlMatch) {
      console.log(chalk.bold.green('\n✅ Deployed successfully!\n'));
      console.log(chalk.white(`  URL: ${chalk.cyan(urlMatch[0])}`));
      console.log(chalk.white(`  Discovery: ${chalk.cyan(urlMatch[0] + '/.well-known/x402')}`));
      console.log();
    }

  } catch (error) {
    console.error(chalk.red('Deployment failed:'));
    if (error instanceof Error) {
      console.error(chalk.gray(error.message));
    }
    process.exit(1);
  }
}
