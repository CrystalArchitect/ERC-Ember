// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MaintenancePool.sol";
import "./mocks/MockUSDC.sol";

contract PoolGovernor {
    function queueDraw(MaintenancePool pool, uint256 amount, address to) external returns (uint256) {
        return pool.queueDraw(amount, to, "draw");
    }

    function queueGovernor(MaintenancePool pool, address next) external returns (uint256) {
        return pool.queueGovernorChange(next);
    }

    function queueSunset(MaintenancePool pool, address recipient) external returns (uint256) {
        return pool.queueSunset(recipient, "sunset");
    }

    function cancel(MaintenancePool pool, uint256 id) external {
        pool.cancel(id);
    }
}

contract MockEmberCode {}

contract MaintenancePoolTest is Test {
    MockUSDC usdc;
    MockEmberCode token;
    PoolGovernor governor;
    PoolGovernor nextGovernor;
    MaintenancePool pool;
    address recipient = makeAddr("recipient");
    uint256 constant DELAY = 2 days;

    function setUp() public {
        usdc = new MockUSDC();
        token = new MockEmberCode();
        governor = new PoolGovernor();
        nextGovernor = new PoolGovernor();
        pool = new MaintenancePool(address(token), address(governor), address(usdc), DELAY);
        usdc.mint(address(this), 1_000_000);
        usdc.approve(address(pool), type(uint256).max);
        pool.tip(1_000_000, "irreversible governor-trusted donation");
    }

    function test_GovernorRotationInvalidatesAllOldProposalsSameEta() public {
        uint256 drawId = governor.queueDraw(pool, 100_000, recipient);
        uint256 rotationId = governor.queueGovernor(pool, address(nextGovernor));
        vm.warp(block.timestamp + DELAY);
        pool.execute(rotationId);
        assertEq(pool.governanceEpoch(), 1);
        vm.expectRevert(bytes("stale proposal"));
        pool.execute(drawId);
    }

    function test_OldGovernorChangeCannotRetakeGovernance() public {
        PoolGovernor attackerGovernor = new PoolGovernor();
        uint256 staleTakeover = governor.queueGovernor(pool, address(attackerGovernor));
        uint256 validRotation = governor.queueGovernor(pool, address(nextGovernor));
        vm.warp(block.timestamp + DELAY);
        pool.execute(validRotation);
        vm.expectRevert(bytes("stale proposal"));
        pool.execute(staleTakeover);
    }

    function test_SunsetPendingBlocksFundingAndCancelReopens() public {
        vm.warp(block.timestamp + pool.SUNSET_INACTIVITY() + 1);
        uint256 id = governor.queueSunset(pool, recipient);
        usdc.mint(address(this), 1);
        vm.expectRevert(bytes("funding closed"));
        pool.tip(1, "blocked");
        governor.cancel(pool, id);
        pool.tip(1, "open again");
    }

    function test_FundingAllowedWhenSunsetEligibleButNotPending() public {
        vm.warp(block.timestamp + pool.SUNSET_INACTIVITY() + 1);
        usdc.mint(address(this), 1);
        pool.tip(1, "still open");
    }
}
