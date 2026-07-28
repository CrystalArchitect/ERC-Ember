// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/EmberFactory.sol";
import "../src/IEmber.sol";

contract DeployProject is Script {
    function run() external returns (address ember, address pool) {
        require(block.chainid == vm.envUint("EXPECTED_CHAIN_ID"), "chain id mismatch");
        uint256 key = vm.envUint("PROJECT_DEPLOYER_PRIVATE_KEY");
        EmberFactory factory = EmberFactory(vm.envAddress("EMBER_FACTORY"));
        require(key != 0 && address(factory).code.length > 0, "bad environment");
        IEmber.SourceManifest memory source = IEmber.SourceManifest({
            archiveHash: vm.envBytes32("ARCHIVE_HASH"),
            fileTreeMerkleRoot: vm.envBytes32("FILE_TREE_MERKLE_ROOT"),
            lockfileHash: vm.envBytes32("LOCKFILE_HASH"),
            buildArtifactHash: vm.envBytes32("BUILD_ARTIFACT_HASH"),
            spdxLicense: vm.envString("SPDX_LICENSE"),
            manifestCID: vm.envString("MANIFEST_CID")
        });
        vm.startBroadcast(key);
        (ember, pool) = factory.deploy(
            vm.envString("PROJECT_NAME"),
            vm.envString("PROJECT_SYMBOL"),
            vm.envUint("MAX_SUPPLY"),
            vm.envAddress("DAPP"),
            vm.envBytes32("ORIGINAL_COMMITMENT"),
            vm.envString("ORIGINAL_ENCRYPTED_CID"),
            source,
            vm.envUint("CREDIT_PRICE"),
            vm.envUint("FUNDING_THRESHOLD"),
            vm.envUint("SALE_DURATION"),
            vm.envBool("SPAWN_MAINTENANCE_POOL"),
            vm.envAddress("POOL_GOVERNOR"),
            vm.envUint("POOL_TIMELOCK_DELAY"),
            vm.envBytes32("PARENT_DEPLOYMENT")
        );
        vm.stopBroadcast();
    }
}
