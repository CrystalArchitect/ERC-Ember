// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./EmberFactory.sol";
import "./EmberCoreFactory.sol";
import "./MaintenancePoolFactory.sol";

/// @title EmberSuiteDeployer — atomic, permissionless factory-suite deployment
/// @notice Deploy this constructor once per version. Child creation bytecode is
/// confined to initcode; the deployed helper retains no administrative power.
contract EmberSuiteDeployer {
    address public immutable emberFactory;
    address public immutable coreFactory;
    address public immutable poolFactory;

    event SuiteDeployed(
        address indexed emberFactory, address indexed coreFactory, address indexed poolFactory, address canonicalUsdc
    );

    constructor(address canonicalUsdc) {
        require(canonicalUsdc != address(0), "no canonical USDC");
        EmberCoreFactory cores = new EmberCoreFactory();
        MaintenancePoolFactory pools = new MaintenancePoolFactory();
        EmberFactory factory = new EmberFactory(address(cores), address(pools), canonicalUsdc);
        cores.bindEmberFactory(address(factory));
        pools.bindEmberFactory(address(factory));
        emberFactory = address(factory);
        coreFactory = address(cores);
        poolFactory = address(pools);
        emit SuiteDeployed(address(factory), address(cores), address(pools), canonicalUsdc);
    }
}
