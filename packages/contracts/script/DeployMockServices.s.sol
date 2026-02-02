// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/ServiceFactory.sol";
import "../src/RevenueToken.sol";
import "../src/RevenueSplitter.sol";

/**
 * @title DeployMockServices
 * @notice Deploy sample tokenized services with mock revenue for demo
 *
 * Usage:
 *   FACTORY_ADDRESS=0x... forge script script/DeployMockServices.s.sol --rpc-url base_sepolia --broadcast
 *
 * This creates 5 demo services and simulates revenue deposits.
 */
contract DeployMockServices is Script {
    // Mock USDC on Base Sepolia (we'll use a simple ERC20 for testing)
    address constant MOCK_USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // Base Sepolia USDC

    struct MockService {
        string name;
        string symbol;
        string category;
        string endpoint;
        uint256 totalSupply;
        uint256 operatorBps;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address factory = vm.envAddress("FACTORY_ADDRESS");

        console.log("Deploying mock services via factory:", factory);

        MockService[5] memory services = [
            MockService({
                name: "GPT-5 Proxy API",
                symbol: "GPT5",
                category: "ai",
                endpoint: "https://gpt5-proxy.x402.demo/v1/chat",
                totalSupply: 1_000_000 ether,
                operatorBps: 2000 // 20%
            }),
            MockService({
                name: "Stable Diffusion XL",
                symbol: "SDXL",
                category: "media",
                endpoint: "https://sdxl.x402.demo/generate",
                totalSupply: 500_000 ether,
                operatorBps: 1500 // 15%
            }),
            MockService({
                name: "Code Assistant Pro",
                symbol: "CODE",
                category: "tools",
                endpoint: "https://codeassist.x402.demo/complete",
                totalSupply: 2_000_000 ether,
                operatorBps: 2500 // 25%
            }),
            MockService({
                name: "Real-time Data Feed",
                symbol: "DATA",
                category: "data",
                endpoint: "https://datafeed.x402.demo/stream",
                totalSupply: 750_000 ether,
                operatorBps: 3000 // 30%
            }),
            MockService({
                name: "Voice Clone API",
                symbol: "VOIC",
                category: "media",
                endpoint: "https://voiceclone.x402.demo/synthesize",
                totalSupply: 300_000 ether,
                operatorBps: 2000 // 20%
            })
        ];

        vm.startBroadcast(deployerPrivateKey);

        for (uint256 i = 0; i < services.length; i++) {
            MockService memory s = services[i];

            // Create unique salt
            bytes32 salt = keccak256(abi.encodePacked(s.name, s.symbol, block.timestamp, i));

            // Deploy via factory
            // Deployer is both operator and treasury (receives 100% of tokens initially)
            (address token, address splitter) = ServiceFactory(factory).deploy(
                s.name,
                s.symbol,
                s.totalSupply,
                s.operatorBps,
                msg.sender,    // treasury = deployer
                s.endpoint,
                s.category,
                salt
            );

            console.log("---");
            console.log("Service:", s.name);
            console.log("  Token:", token);
            console.log("  Splitter:", splitter);
            console.log("  Category:", s.category);
        }

        vm.stopBroadcast();

        console.log("\n=== MOCK SERVICES DEPLOYED ===");
        console.log("Run the indexer to see them in the web app!");
    }
}
