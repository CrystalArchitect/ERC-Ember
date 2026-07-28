// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/EmberSuiteDeployer.sol";
import "../src/EmberFactory.sol";
import "../src/EmberCore.sol";
import "../src/MaintenancePool.sol";
import "./mocks/MockUSDC.sol";

contract FactoryDApp {}

contract FactoryGovernor {}

contract EmberFactoryPoolTest is Test {
    MockUSDC usdc;
    EmberFactory factory;
    MaintenancePoolFactory poolFactory;
    FactoryDApp dapp;
    FactoryGovernor governor;
    address developer = makeAddr("developer");

    function setUp() public {
        usdc = new MockUSDC();
        dapp = new FactoryDApp();
        governor = new FactoryGovernor();
        EmberSuiteDeployer suite = new EmberSuiteDeployer(address(usdc));
        address factoryAddress = suite.emberFactory();
        address poolAddress = suite.poolFactory();
        factory = EmberFactory(factoryAddress);
        poolFactory = MaintenancePoolFactory(poolAddress);
    }

    function _manifest(string memory declaration) internal pure returns (IEmber.SourceManifest memory) {
        return IEmber.SourceManifest({
            archiveHash: keccak256("a"),
            fileTreeMerkleRoot: keccak256("t"),
            lockfileHash: keccak256("l"),
            buildArtifactHash: keccak256("b"),
            spdxLicense: declaration,
            manifestCID: "ipfs://m"
        });
    }

    function _deploy(bool withPool, string memory declaration) internal returns (address ember, address pool) {
        vm.prank(developer);
        return factory.deploy(
            "Project",
            "PRJ",
            100,
            address(dapp),
            keccak256("key"),
            "ipfs://e",
            _manifest(declaration),
            10_000,
            25,
            30 days,
            withPool,
            withPool ? address(governor) : address(0),
            7 days,
            bytes32(0)
        );
    }

    function test_SuiteIsAtomicallyAndIrrevocablyBound() public view {
        assertEq(poolFactory.emberFactory(), address(factory));
        assertEq(address(factory.POOL_FACTORY()), address(poolFactory));
        assertEq(factory.CORE_FACTORY().emberFactory(), address(factory));
        assertEq(factory.CANONICAL_USDC(), address(usdc));
    }

    function test_DeploymentIsPermissionlessAndDeclarationIsUnverifiedData() public {
        (address ember,) = _deploy(false, "LicenseRef-Proprietary-1");
        (address registeredDev,, address pool,, bytes32 declarationHash) = factory.info(ember);
        assertEq(registeredDev, developer);
        assertEq(pool, address(0));
        assertEq(declarationHash, keccak256(bytes("LicenseRef-Proprietary-1")));
        assertEq(EmberCore(ember).developer(), developer);
    }

    function test_RegistryStoresActualCanonicalPool() public {
        (address ember, address pool) = _deploy(true, "MIT");
        (,, address registeredPool,,) = factory.info(ember);
        assertEq(registeredPool, pool);
        assertEq(factory.poolForEmber(ember), pool);
        assertEq(poolFactory.poolForEmber(ember), pool);
        assertEq(MaintenancePool(pool).governor(), address(governor));
    }

    function test_RejectsEmptyOrOverlongDeclaration() public {
        vm.expectRevert(bytes("bad SPDX declaration"));
        _deploy(false, "");
        vm.expectRevert(bytes("bad SPDX declaration"));
        _deploy(
            false,
            "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
        );
    }

    function test_NoOwnerOrFeeSelectorsExist() public {
        (bool ownerOk,) = address(factory).staticcall(abi.encodeWithSignature("owner()"));
        (bool feeOk,) = address(factory).staticcall(abi.encodeWithSignature("FACTORY_FEE_BPS()"));
        assertFalse(ownerOk);
        assertFalse(feeOk);
    }
}
