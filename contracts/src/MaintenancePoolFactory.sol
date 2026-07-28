// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./MaintenancePool.sol";

/// @title MaintenancePoolFactory — irrevocably bound companion factory
contract MaintenancePoolFactory {
    address public immutable suiteDeployer;
    address public emberFactory;
    mapping(address => address) public poolForEmber;

    event PoolCreated(address indexed pool, address indexed emberToken, address governor);
    event EmberFactoryBound(address indexed emberFactory);

    constructor() {
        suiteDeployer = msg.sender;
    }

    function bindEmberFactory(address factory) external {
        require(msg.sender == suiteDeployer, "not suite deployer");
        require(emberFactory == address(0), "factory bound");
        require(factory != address(0) && factory.code.length > 0, "factory not contract");
        emberFactory = factory;
        emit EmberFactoryBound(factory);
    }

    function create(address emberToken, address governor, address usdc, uint256 timelockDelay)
        external
        returns (address pool)
    {
        require(msg.sender == emberFactory, "not factory");
        require(emberToken != address(0), "no ember");
        require(governor != address(0), "no governor");
        require(usdc != address(0), "no USDC");
        require(timelockDelay >= 1 days, "delay too short");
        require(timelockDelay <= 30 days, "delay too long");
        require(poolForEmber[emberToken] == address(0), "pool exists");
        pool = address(new MaintenancePool(emberToken, governor, usdc, timelockDelay));
        poolForEmber[emberToken] = pool;
        emit PoolCreated(pool, emberToken, governor);
    }
}
