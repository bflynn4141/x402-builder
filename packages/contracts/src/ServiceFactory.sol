// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./RevenueToken.sol";
import "./RevenueSplitter.sol";

/**
 * @title ServiceFactory
 * @notice Factory for deploying tokenized x402 services with CREATE2
 * @dev Deterministic addresses allow prediction before deployment
 *
 * Deploys:
 * 1. RevenueToken - ERC-20 with built-in dividend distribution
 * 2. RevenueSplitter - Receives x402 payments, splits to operator + holders
 */
contract ServiceFactory {
    /// @notice Registry to auto-register new services
    address public immutable registry;

    /// @notice Track all deployed services
    struct DeployedService {
        address token;
        address splitter;
        address operator;
        uint256 deployedAt;
    }

    /// @notice All deployed services
    DeployedService[] public services;

    /// @notice Operator => their services
    mapping(address => address[]) public operatorServices;

    /// @notice Token => DeployedService index + 1
    mapping(address => uint256) public tokenToIndex;

    event ServiceDeployed(
        address indexed token,
        address indexed splitter,
        address indexed operator,
        string name,
        string symbol,
        uint256 totalSupply,
        uint256 operatorBps
    );

    error ZeroAddress();
    error ServiceExists();

    /**
     * @param _registry ServiceRegistry address for auto-registration
     */
    constructor(address _registry) {
        registry = _registry;
    }

    /**
     * @notice Deploy a new tokenized x402 service
     * @param name Token name
     * @param symbol Token symbol
     * @param totalSupply Total token supply (18 decimals)
     * @param operatorShareBps Operator's share of token supply in basis points (e.g., 2000 = 20%)
     * @param treasury Address to receive non-operator tokens (for sale/distribution)
     * @param endpoint Primary x402 endpoint URL
     * @param category Service category (ai, data, tools, etc.)
     * @param salt Unique salt for CREATE2 (use keccak256(name, symbol, operator))
     * @return token RevenueToken address
     * @return splitter RevenueSplitter address (this is the x402 payment receiver)
     */
    function deploy(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        uint256 operatorShareBps,
        address treasury,
        string memory endpoint,
        string memory category,
        bytes32 salt
    ) external returns (address token, address splitter) {
        // Combine salt with sender for uniqueness
        bytes32 finalSalt = keccak256(abi.encodePacked(salt, msg.sender));

        // Deploy RevenueToken with CREATE2
        // Operator gets operatorShareBps% of supply, treasury gets the rest
        token = address(new RevenueToken{salt: finalSalt}(
            name,
            symbol,
            msg.sender,      // operator
            treasury,        // receives non-operator tokens
            totalSupply,
            operatorShareBps,
            endpoint,
            category
        ));

        // Deploy RevenueSplitter with CREATE2
        // Use different salt for splitter
        bytes32 splitterSalt = keccak256(abi.encodePacked(finalSalt, "splitter"));
        splitter = address(new RevenueSplitter{salt: splitterSalt}(token));

        // Track deployment
        services.push(DeployedService({
            token: token,
            splitter: splitter,
            operator: msg.sender,
            deployedAt: block.timestamp
        }));

        uint256 index = services.length;
        tokenToIndex[token] = index;
        operatorServices[msg.sender].push(token);

        // Auto-register in ServiceRegistry if available
        if (registry != address(0)) {
            try IServiceRegistry(registry).registerFor(
                token,
                splitter,
                msg.sender, // operator passed explicitly (no tx.origin)
                name,
                category,
                endpoint,
                operatorShareBps
            ) {} catch {
                // Registry may not be deployed or may reject
                // Continue anyway - service is still functional
            }
        }

        emit ServiceDeployed(
            token,
            splitter,
            msg.sender,
            name,
            symbol,
            totalSupply,
            operatorShareBps
        );
    }

    /**
     * @notice Predict deployment addresses before deploying
     * @param name Token name
     * @param symbol Token symbol
     * @param operator Operator address (msg.sender when deploying)
     * @param treasury Treasury address for non-operator tokens
     * @param totalSupply Total token supply
     * @param operatorShareBps Operator's share of token supply in basis points
     * @param endpoint Primary x402 endpoint
     * @param category Service category
     * @param salt User-provided salt
     * @return token Predicted RevenueToken address
     * @return splitter Predicted RevenueSplitter address
     */
    function predictAddresses(
        string memory name,
        string memory symbol,
        address operator,
        address treasury,
        uint256 totalSupply,
        uint256 operatorShareBps,
        string memory endpoint,
        string memory category,
        bytes32 salt
    ) external view returns (address token, address splitter) {
        bytes32 finalSalt = keccak256(abi.encodePacked(salt, operator));

        // Predict token address
        bytes memory tokenBytecode = abi.encodePacked(
            type(RevenueToken).creationCode,
            abi.encode(name, symbol, operator, treasury, totalSupply, operatorShareBps, endpoint, category)
        );
        token = address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            finalSalt,
            keccak256(tokenBytecode)
        )))));

        // Predict splitter address
        bytes32 splitterSalt = keccak256(abi.encodePacked(finalSalt, "splitter"));
        bytes memory splitterBytecode = abi.encodePacked(
            type(RevenueSplitter).creationCode,
            abi.encode(token)
        );
        splitter = address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            splitterSalt,
            keccak256(splitterBytecode)
        )))));
    }

    /**
     * @notice Get total number of deployed services
     */
    function getServiceCount() external view returns (uint256) {
        return services.length;
    }

    /**
     * @notice Get services deployed by an operator
     */
    function getOperatorServices(address operator) external view returns (address[] memory) {
        return operatorServices[operator];
    }

    /**
     * @notice Get service details by token address
     */
    function getService(address token) external view returns (DeployedService memory) {
        uint256 index = tokenToIndex[token];
        require(index > 0, "Service not found");
        return services[index - 1];
    }
}

interface IServiceRegistry {
    function registerFor(
        address token,
        address splitter,
        address operator,
        string memory name,
        string memory category,
        string memory endpoint,
        uint256 operatorBps
    ) external;
}
