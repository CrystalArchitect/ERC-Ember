// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/StdInvariant.sol";
import "forge-std/Test.sol";
import "../src/EmberCore.sol";
import "./mocks/MockUSDC.sol";

contract InvariantDApp {}

contract EmberV1Handler is Test {
    EmberCore public immutable ember;
    MockUSDC public immutable usdc;
    address public immutable dapp;
    address public immutable developer;
    address[3] public actors;
    uint256 public usageNonce;

    constructor(EmberCore e, MockUSDC u, address app, address dev, address[3] memory users) {
        ember = e;
        usdc = u;
        dapp = app;
        developer = dev;
        actors = users;
    }

    function buy(uint256 seed, uint256 rawAmount) external {
        if (ember.saleClosed() || block.timestamp > ember.saleDeadline()) return;
        uint256 inventory = ember.balanceOf(address(ember));
        if (inventory == 0) return;
        uint256 amount = bound(rawAmount, 1, inventory);
        address actor = actors[seed % actors.length];
        uint256 cost = ember.quote(amount);
        usdc.mint(actor, cost);
        vm.startPrank(actor);
        usdc.approve(address(ember), cost);
        ember.buy(amount, cost);
        vm.stopPrank();
    }

    function burn(uint256 seed, uint256 rawAmount) external {
        if (!ember.funded() || ember.abandoned() || ember.releaseDeadline() != 0) return;
        address actor = actors[seed % actors.length];
        uint256 balance = ember.balanceOf(actor);
        if (balance == 0) return;
        uint256 amount = bound(rawAmount, 1, balance);
        vm.prank(actor);
        ember.approveBurn(dapp, amount);
        vm.prank(dapp);
        ember.useApp(actor, amount, bytes32(++usageNonce));
    }

    function withdraw() external {
        if (!ember.funded() || ember.devClaimable() == 0) return;
        vm.prank(developer);
        ember.withdrawDev();
    }

    function close() external {
        if (ember.saleClosed()) return;
        if (ember.funded()) {
            vm.warp(ember.saleStart() + ember.MIN_SALE_DURATION());
            vm.prank(developer);
            ember.closeSale();
        } else {
            vm.warp(ember.saleDeadline() + 1);
            ember.closeSale();
        }
    }

    function redeem(uint256 seed, uint256 rawAmount) external {
        if (!ember.redemptionEnabled()) return;
        address actor = actors[seed % actors.length];
        uint256 balance = ember.balanceOf(actor);
        if (balance == 0) return;
        uint256 amount = bound(rawAmount, 1, balance);
        vm.prank(actor);
        ember.redeem(amount);
    }
}

contract EmberCoreInvariantTest is StdInvariant, Test {
    MockUSDC usdc;
    EmberCore ember;
    EmberV1Handler handler;
    address developer = address(0xD3);
    address[3] actors = [address(0xA1), address(0xA2), address(0xA3)];

    function setUp() public {
        usdc = new MockUSDC();
        InvariantDApp app = new InvariantDApp();
        IEmber.SourceManifest memory source = IEmber.SourceManifest({
            archiveHash: keccak256("a"),
            fileTreeMerkleRoot: keccak256("t"),
            lockfileHash: keccak256("l"),
            buildArtifactHash: keccak256("b"),
            spdxLicense: "MIT",
            manifestCID: "ipfs://m"
        });
        ember = new EmberCore(
            "Invariant",
            "INV",
            100,
            developer,
            address(app),
            keccak256("key"),
            "ipfs://e",
            source,
            address(usdc),
            10_000,
            25,
            30 days
        );
        handler = new EmberV1Handler(ember, usdc, address(app), developer, actors);
        targetContract(address(handler));
    }

    function invariant_ExactSolvency() public view {
        assertEq(usdc.balanceOf(address(ember)), ember.totalLiabilities(), "USDC != exact liabilities");
    }

    function invariant_CreditConservation() public view {
        uint256 live = ember.outstandingLiveCredits();
        assertEq(ember.tokensSold(), live + ember.totalBurned() + ember.totalRedeemed(), "sold credits not conserved");
        assertLe(ember.tokensSold(), ember.INITIAL_SUPPLY());
    }

    function invariant_FeeFree() public view {
        assertEq(ember.totalRaised(), ember.tokensSold() * ember.creditPrice());
        assertEq(ember.developerPerCredit() + ember.releaseReservePerCredit(), ember.creditPrice());
    }
}
