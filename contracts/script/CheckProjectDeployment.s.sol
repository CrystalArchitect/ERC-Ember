// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/EmberCore.sol";
import "../src/EmberFactory.sol";
import "../src/MaintenancePool.sol";

contract CheckProjectDeployment is Script {
    function run() external view {
        require(block.chainid == vm.envUint("EXPECTED_CHAIN_ID"), "chain id mismatch");
        EmberFactory factory = EmberFactory(vm.envAddress("EMBER_FACTORY"));
        EmberCore ember = EmberCore(vm.envAddress("EMBER_PROJECT"));
        require(address(ember).code.length > 0, "project has no code");
        require(address(ember.USDC()) == factory.CANONICAL_USDC(), "USDC mismatch");
        require(ember.creditPrice() == vm.envUint("CREDIT_PRICE"), "price mismatch");
        require(ember.fundingThreshold() == vm.envUint("FUNDING_THRESHOLD"), "threshold mismatch");
        (address developer,, address pool, bytes32 parent, bytes32 declarationHash) = factory.info(address(ember));
        require(developer == vm.envAddress("PROJECT_DEVELOPER"), "developer mismatch");
        require(pool == factory.poolForEmber(address(ember)), "pool mapping mismatch");
        require(parent == vm.envBytes32("PARENT_DEPLOYMENT"), "parent mismatch");
        require(declarationHash == keccak256(bytes(vm.envString("SPDX_LICENSE"))), "declaration mismatch");
        if (pool != address(0)) {
            require(MaintenancePool(pool).emberToken() == address(ember), "pool project mismatch");
        }
    }
}
