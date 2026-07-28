// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/EmberFactory.sol";
import "../src/MaintenancePoolFactory.sol";

contract CheckFactoryDeployment is Script {
    function run() external view {
        require(block.chainid == vm.envUint("EXPECTED_CHAIN_ID"), "chain id mismatch");
        EmberFactory factory = EmberFactory(vm.envAddress("EMBER_FACTORY"));
        MaintenancePoolFactory pools = MaintenancePoolFactory(vm.envAddress("MAINTENANCE_POOL_FACTORY"));
        require(address(factory).code.length > 0 && address(pools).code.length > 0, "missing code");
        require(factory.CANONICAL_USDC() == vm.envAddress("CANONICAL_USDC"), "USDC mismatch");
        require(address(factory.POOL_FACTORY()) == address(pools), "pool factory mismatch");
        require(pools.emberFactory() == address(factory), "suite not bound");
    }
}
