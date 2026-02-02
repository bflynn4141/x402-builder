// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/ServiceLauncher.sol";

/**
 * @title DeployServiceLauncher
 * @notice Deploy the ServiceLauncher for one-click x402 + CCA token launches
 *
 * Usage:
 *   source .env && forge script script/DeployServiceLauncher.s.sol --rpc-url $BASE_RPC_URL --broadcast --verify
 */
contract DeployServiceLauncher is Script {
    // LiquidityLauncher on Base mainnet (canonical address)
    address constant LIQUIDITY_LAUNCHER = 0x00000008412db3394C91A5CbD01635c6d140637C;

    // FullRangeLBPStrategyFactory on Base mainnet
    address constant LBP_STRATEGY_FACTORY = 0x39E5eB34dD2c8082Ee1e556351ae660F33B04252;

    // CCA Factory on Base mainnet
    address constant CCA_FACTORY = 0xCCccCcCAE7503Cac057829BF2811De42E16e0bD5;

    // Uniswap v4 PoolManager on Base mainnet
    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;

    // ServiceRegistry deployed earlier
    address constant REGISTRY = 0x221afa2dC521eebF0044Ea3bcA5c58dd57F40e7C;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance);
        console.log("");
        console.log("Using LiquidityLauncher:", LIQUIDITY_LAUNCHER);
        console.log("Using LBP Strategy Factory:", LBP_STRATEGY_FACTORY);
        console.log("Using CCA Factory:", CCA_FACTORY);
        console.log("Using PoolManager:", POOL_MANAGER);
        console.log("Using Registry:", REGISTRY);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy ServiceLauncher
        ServiceLauncher launcher = new ServiceLauncher(
            LIQUIDITY_LAUNCHER,
            LBP_STRATEGY_FACTORY,
            CCA_FACTORY,
            POOL_MANAGER,
            REGISTRY
        );
        console.log("");
        console.log("ServiceLauncher deployed at:", address(launcher));

        vm.stopBroadcast();

        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("LAUNCHER_ADDRESS=%s", address(launcher));
        console.log("===========================");
        console.log("");
        console.log("Next steps:");
        console.log("1. Update MCP server with LAUNCHER_ADDRESS");
        console.log("2. Test with: x402_launch name='Test' symbol='TEST' ...");
    }
}
