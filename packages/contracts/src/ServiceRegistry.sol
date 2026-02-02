// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ServiceRegistry
 * @notice Registry of tokenized x402 services for discovery
 * @dev Services register here to be discoverable by agents and the web app
 */
contract ServiceRegistry is Ownable {
    struct Service {
        address token;           // RevenueToken address
        address splitter;        // RevenueSplitter address (x402 payment receiver)
        address operator;        // Service operator
        string name;             // Human-readable name
        string category;         // ai, data, tools, media, infrastructure, other
        string endpoint;         // Primary x402 endpoint URL
        uint256 operatorBps;     // Operator's share in basis points
        uint256 registeredAt;    // Registration timestamp
        bool active;             // Whether service is active
    }

    /// @notice All registered services
    Service[] public services;

    /// @notice Token address => service index + 1 (0 means not found)
    mapping(address => uint256) public tokenToIndex;

    /// @notice Splitter address => token address
    mapping(address => address) public splitterToToken;

    /// @notice Category => list of token addresses
    mapping(string => address[]) public categoryToTokens;

    /// @notice Authorized factories that can register services
    mapping(address => bool) public authorizedFactories;

    event ServiceRegistered(
        address indexed token,
        address indexed splitter,
        address indexed operator,
        string name,
        string category
    );

    event ServiceUpdated(address indexed token, string endpoint, bool active);
    event FactoryAuthorized(address indexed factory, bool authorized);

    error ServiceAlreadyRegistered();
    error ServiceNotFound();
    error NotOperator();
    error NotAuthorized();
    error ZeroAddress();
    error InvalidBps();

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Authorize a factory to register services
     */
    function setFactory(address factory, bool authorized) external onlyOwner {
        authorizedFactories[factory] = authorized;
        emit FactoryAuthorized(factory, authorized);
    }

    /**
     * @notice Register a new x402 service (for direct operator calls)
     * @param token RevenueToken contract address
     * @param splitter RevenueSplitter address (x402 payment receiver)
     * @param name Human-readable service name
     * @param category Service category (ai, data, tools, media, etc.)
     * @param endpoint Primary x402 endpoint URL
     * @param operatorBps Operator's share in basis points
     */
    function register(
        address token,
        address splitter,
        string memory name,
        string memory category,
        string memory endpoint,
        uint256 operatorBps
    ) external {
        _register(token, splitter, msg.sender, name, category, endpoint, operatorBps);
    }

    /**
     * @notice Register a new x402 service (for authorized factories)
     * @param token RevenueToken contract address
     * @param splitter RevenueSplitter address (x402 payment receiver)
     * @param operator Service operator address
     * @param name Human-readable service name
     * @param category Service category (ai, data, tools, media, etc.)
     * @param endpoint Primary x402 endpoint URL
     * @param operatorBps Operator's share in basis points
     */
    function registerFor(
        address token,
        address splitter,
        address operator,
        string memory name,
        string memory category,
        string memory endpoint,
        uint256 operatorBps
    ) external {
        if (!authorizedFactories[msg.sender]) revert NotAuthorized();
        _register(token, splitter, operator, name, category, endpoint, operatorBps);
    }

    /**
     * @dev Internal registration logic
     */
    function _register(
        address token,
        address splitter,
        address operator,
        string memory name,
        string memory category,
        string memory endpoint,
        uint256 operatorBps
    ) internal {
        if (token == address(0) || splitter == address(0) || operator == address(0)) revert ZeroAddress();
        if (tokenToIndex[token] != 0) revert ServiceAlreadyRegistered();
        if (operatorBps > 10000) revert InvalidBps();

        services.push(Service({
            token: token,
            splitter: splitter,
            operator: operator,
            name: name,
            category: category,
            endpoint: endpoint,
            operatorBps: operatorBps,
            registeredAt: block.timestamp,
            active: true
        }));

        uint256 index = services.length; // 1-indexed
        tokenToIndex[token] = index;
        splitterToToken[splitter] = token;
        categoryToTokens[category].push(token);

        emit ServiceRegistered(token, splitter, operator, name, category);
    }

    /**
     * @notice Update service details
     * @param token RevenueToken address
     * @param endpoint New endpoint URL (empty string to keep current)
     * @param active Whether service is active
     */
    function updateService(
        address token,
        string memory endpoint,
        bool active
    ) external {
        uint256 index = tokenToIndex[token];
        if (index == 0) revert ServiceNotFound();

        Service storage service = services[index - 1];
        if (msg.sender != service.operator && msg.sender != owner()) revert NotOperator();

        if (bytes(endpoint).length > 0) {
            service.endpoint = endpoint;
        }
        service.active = active;

        emit ServiceUpdated(token, endpoint, active);
    }

    /**
     * @notice Get total number of registered services
     */
    function getServiceCount() external view returns (uint256) {
        return services.length;
    }

    /**
     * @notice Get service by token address
     */
    function getService(address token) external view returns (Service memory) {
        uint256 index = tokenToIndex[token];
        if (index == 0) revert ServiceNotFound();
        return services[index - 1];
    }

    /**
     * @notice Get service by splitter address
     */
    function getServiceBySplitter(address splitter) external view returns (Service memory) {
        address token = splitterToToken[splitter];
        if (token == address(0)) revert ServiceNotFound();
        return services[tokenToIndex[token] - 1];
    }

    /**
     * @notice Get all services in a category
     * @param category Category to filter by
     * @return tokens Array of token addresses in the category
     */
    function getServicesByCategory(string memory category) external view returns (address[] memory) {
        return categoryToTokens[category];
    }

    /**
     * @notice Get paginated list of services
     * @param offset Starting index
     * @param limit Max number to return
     */
    function getServices(uint256 offset, uint256 limit) external view returns (Service[] memory) {
        if (offset >= services.length) {
            return new Service[](0);
        }

        uint256 end = offset + limit;
        if (end > services.length) {
            end = services.length;
        }

        Service[] memory result = new Service[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = services[i];
        }

        return result;
    }

    /**
     * @notice Get all active services (for discovery)
     */
    function getActiveServices() external view returns (Service[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < services.length; i++) {
            if (services[i].active) activeCount++;
        }

        Service[] memory result = new Service[](activeCount);
        uint256 j = 0;
        for (uint256 i = 0; i < services.length; i++) {
            if (services[i].active) {
                result[j++] = services[i];
            }
        }

        return result;
    }
}
