// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/ServiceRegistry.sol";
import "../src/ServiceFactory.sol";

/**
 * @title Deploy
 * @notice Deploy ServiceRegistry and ServiceFactory to Base Sepolia
 *
 * Usage:
 *   forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast --verify
 *
 * Required env vars:
 *   PRIVATE_KEY - Deployer private key
 *   BASESCAN_API_KEY - For contract verification
 */
contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy ServiceRegistry
        ServiceRegistry registry = new ServiceRegistry();
        console.log("ServiceRegistry deployed at:", address(registry));

        // 2. Deploy ServiceFactory with registry
        ServiceFactory factory = new ServiceFactory(address(registry));
        console.log("ServiceFactory deployed at:", address(factory));

        // 3. Authorize factory to register services
        registry.setFactory(address(factory), true);
        console.log("Factory authorized in registry");

        vm.stopBroadcast();

        // Output for easy copy-paste
        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("REGISTRY_ADDRESS=%s", address(registry));
        console.log("FACTORY_ADDRESS=%s", address(factory));
        console.log("===========================\n");
    }
}
