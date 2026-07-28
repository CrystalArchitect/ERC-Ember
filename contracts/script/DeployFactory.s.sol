// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/EmberSuiteDeployer.sol";

/// @notice Atomically deploys and binds the adminless canonical factory suite.
contract DeployFactory is Script {
    function run() external returns (address emberFactory, address poolFactory) {
        require(block.chainid == vm.envUint("EXPECTED_CHAIN_ID"), "chain id mismatch");
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address canonicalUsdc = vm.envAddress("CANONICAL_USDC");
        require(key != 0 && canonicalUsdc != address(0), "bad environment");
        vm.startBroadcast(key);
        EmberSuiteDeployer deployer = new EmberSuiteDeployer(canonicalUsdc);
        emberFactory = deployer.emberFactory();
        poolFactory = deployer.poolFactory();
        vm.stopBroadcast();
    }
}
