// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/EmberCore.sol";
import "./mocks/MockUSDC.sol";
import "./mocks/MockWeirdUSDC.sol";

contract MockDApp {
    function tryTransferFrom(EmberCore token, address from, address to, uint256 amount) external returns (bool) {
        return token.transferFrom(from, to, amount);
    }
}

contract Mock1271Wallet {
    bytes4 constant MAGIC = 0x1626ba7e;
    bytes32 public approvedDigest;

    function approveDigest(bytes32 digest) external {
        approvedDigest = digest;
    }

    function isValidSignature(bytes32 digest, bytes calldata) external view returns (bytes4) {
        return digest == approvedDigest ? MAGIC : bytes4(0xffffffff);
    }
}

contract EmberCoreTest is Test {
    MockUSDC usdc;
    MockDApp dapp;
    EmberCore ember;
    address developer = makeAddr("developer");
    address buyer = makeAddr("buyer");
    uint256 constant SUPPLY = 100;
    uint256 constant PRICE = 10_000;
    string constant KEY = "genesis-key";

    function setUp() public {
        usdc = new MockUSDC();
        dapp = new MockDApp();
        ember = _deploy(address(dapp));
    }

    function _manifest() internal pure returns (IEmber.SourceManifest memory) {
        return IEmber.SourceManifest({
            archiveHash: keccak256("archive"),
            fileTreeMerkleRoot: keccak256("tree"),
            lockfileHash: keccak256("lock"),
            buildArtifactHash: keccak256("build"),
            spdxLicense: "MIT",
            manifestCID: "ipfs://manifest"
        });
    }

    function _deploy(address app) internal returns (EmberCore) {
        return _deployWithToken(app, address(usdc));
    }

    function _deployWithToken(address app, address paymentToken) internal returns (EmberCore) {
        return new EmberCore(
            "Ember",
            "EMB",
            SUPPLY,
            developer,
            app,
            keccak256(bytes(KEY)),
            "ipfs://encrypted",
            _manifest(),
            paymentToken,
            PRICE,
            50,
            30 days
        );
    }

    function _buy(EmberCore target, address account, uint256 amount) internal {
        uint256 cost = target.quote(amount);
        usdc.mint(account, cost);
        vm.startPrank(account);
        usdc.approve(address(target), cost);
        target.buy(amount, cost);
        vm.stopPrank();
    }

    function _burn(EmberCore target, address user, uint256 amount, bytes32 usageId) internal {
        vm.prank(user);
        target.approveBurn(address(dapp), amount);
        vm.prank(address(dapp));
        target.useApp(user, amount, usageId);
    }

    function test_FlatPriceThresholdAndExactLiabilities() public {
        _buy(ember, buyer, 60);
        assertEq(ember.quote(17), PRICE * 17);
        _burn(ember, buyer, 20, keccak256("use-1"));
        assertEq(ember.developerEarned(), 20 * 8_000);
        assertEq(ember.releaseReserveAccrued(), 20 * 2_000);
        assertEq(ember.redemptionLiability(), 40 * PRICE);
        assertEq(ember.totalLiabilities(), usdc.balanceOf(address(ember)));

        vm.prank(developer);
        ember.withdrawDev();
        assertEq(usdc.balanceOf(developer), 160_000);
        assertEq(ember.totalLiabilities(), usdc.balanceOf(address(ember)));
    }

    function test_BurnUsesSeparateExactAllowanceAndIdempotentUsageId() public {
        _buy(ember, buyer, 50);
        vm.prank(buyer);
        ember.approve(address(dapp), 50);
        vm.prank(address(dapp));
        vm.expectRevert(bytes("exact burn allowance"));
        ember.useApp(buyer, 1, keccak256("ordinary-allowance-does-not-burn"));

        vm.prank(buyer);
        ember.approveBurn(address(dapp), 1);
        vm.prank(buyer);
        ember.approve(address(dapp), 0);
        vm.expectRevert(bytes("allowance"));
        dapp.tryTransferFrom(ember, buyer, developer, 1);

        _burn(ember, buyer, 1, keccak256("request"));
        vm.prank(buyer);
        ember.approveBurn(address(dapp), 1);
        vm.prank(address(dapp));
        vm.expectRevert(bytes("usage id used"));
        ember.useApp(buyer, 1, keccak256("request"));
    }

    function test_BuyRejectsNoOpAndFeeOnTransferPaymentTokens() public {
        NoReturnNoOpUSDC noOp = new NoReturnNoOpUSDC();
        EmberCore noOpEmber = _deployWithToken(address(dapp), address(noOp));
        noOp.mint(buyer, PRICE);
        vm.startPrank(buyer);
        noOp.approve(address(noOpEmber), PRICE);
        vm.expectRevert(bytes("USDC pull amount"));
        noOpEmber.buy(1, PRICE);
        vm.stopPrank();

        FeeOnTransferUSDC feeToken = new FeeOnTransferUSDC();
        EmberCore feeEmber = _deployWithToken(address(dapp), address(feeToken));
        feeToken.mint(buyer, PRICE);
        vm.startPrank(buyer);
        feeToken.approve(address(feeEmber), PRICE);
        vm.expectRevert(bytes("USDC pull amount"));
        feeEmber.buy(1, PRICE);
        vm.stopPrank();
    }

    function test_PartialSaleCloseRetiresInventoryAndUsesFinalSoldSupply() public {
        _buy(ember, buyer, 60);
        _burn(ember, buyer, 30, keccak256("half"));
        vm.warp(block.timestamp + ember.MIN_SALE_DURATION());
        vm.prank(developer);
        ember.closeSale();
        assertEq(ember.finalSoldSupply(), 60);
        assertEq(ember.totalSupply(), 30);
        assertEq(ember.totalBurned(), 30);
        _burn(ember, buyer, 30, keccak256("rest"));
        assertGt(ember.releaseDeadline(), 0);
    }

    function test_FailedThresholdRefundsFullPrice() public {
        _buy(ember, buyer, 20);
        vm.warp(ember.saleDeadline() + 1);
        ember.closeSale();
        assertEq(uint8(ember.saleOutcome()), uint8(EmberCore.SaleOutcome.Failed));
        vm.prank(buyer);
        ember.redeem(20);
        assertEq(usdc.balanceOf(buyer), 20 * PRICE);
        assertEq(usdc.balanceOf(address(ember)), 0);
    }

    function test_GraceUntilSlashedAndIncrementalRelease() public {
        _buy(ember, buyer, 50);
        vm.warp(block.timestamp + ember.MIN_SALE_DURATION());
        vm.prank(developer);
        ember.closeSale();
        vm.prank(developer);
        ember.openEmberPhase();
        vm.warp(ember.releaseDeadline() + 1);
        ember.revealKey(0, KEY);
        ember.finalizeRelease();
        assertTrue(ember.released());
        assertEq(ember.devClaimable(), 0); // no consumed credits
    }

    function test_AbandonmentSlashesReserveAndPreservesHolderAndBuilderClaims() public {
        _buy(ember, buyer, 60);
        _burn(ember, buyer, 20, keccak256("consumed"));
        vm.prank(developer);
        ember.withdrawDev();
        vm.warp(ember.lastUserActivity() + ember.ABANDONMENT_TIMEOUT() + 1);
        ember.finalizeAbandonment();
        assertTrue(ember.abandoned());
        assertEq(usdc.balanceOf(address(0xdEaD)), 40_000);
        vm.prank(buyer);
        ember.redeem(40);
        assertEq(usdc.balanceOf(buyer), 400_000);
        assertEq(usdc.balanceOf(address(ember)), 0);
    }

    function test_Eip712AuthorizationReplayExpiryWrongProjectAndWrongChain() public {
        uint256 userKey = 0xA11CE;
        address user = vm.addr(userKey);
        _buy(ember, user, 50);
        bytes32 usageId = keccak256("signed-use");
        uint256 nonce = 7;
        uint256 deadline = block.timestamp + 1 days;
        bytes32 digest = _digest(ember, user, 2, usageId, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.prank(address(dapp));
        ember.useAppWithAuthorization(user, 2, usageId, nonce, deadline, signature);

        vm.prank(address(dapp));
        vm.expectRevert(bytes("nonce used"));
        ember.useAppWithAuthorization(user, 2, keccak256("replay"), nonce, deadline, signature);

        EmberCore other = _deploy(address(dapp));
        _buy(other, user, 50);
        vm.prank(address(dapp));
        vm.expectRevert(bytes("invalid signature"));
        other.useAppWithAuthorization(user, 2, usageId, nonce, deadline, signature);

        uint256 oldChain = block.chainid;
        vm.chainId(oldChain + 1);
        vm.prank(address(dapp));
        vm.expectRevert(bytes("invalid signature"));
        other.useAppWithAuthorization(user, 2, keccak256("chain"), nonce + 1, deadline, signature);
        vm.chainId(oldChain);

        uint256 expiredDeadline = block.timestamp - 1;
        vm.prank(address(dapp));
        vm.expectRevert(bytes("authorization expired"));
        other.useAppWithAuthorization(user, 2, keccak256("expired"), nonce + 2, expiredDeadline, signature);
    }

    function test_Eip1271Authorization() public {
        Mock1271Wallet wallet = new Mock1271Wallet();
        _buy(ember, address(wallet), 50);
        bytes32 usageId = keccak256("1271");
        uint256 deadline = block.timestamp + 1 days;
        bytes32 digest = _digest(ember, address(wallet), 3, usageId, 1, deadline);
        wallet.approveDigest(digest);
        vm.prank(address(dapp));
        ember.useAppWithAuthorization(address(wallet), 3, usageId, 1, deadline, hex"1234");
        assertEq(ember.balanceOf(address(wallet)), 47);
    }

    function _digest(EmberCore target, address user, uint256 amount, bytes32 usageId, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(
            abi.encode(target.USE_AUTHORIZATION_TYPEHASH(), user, address(dapp), amount, usageId, nonce, deadline)
        );
        return keccak256(abi.encodePacked("\x19\x01", target.DOMAIN_SEPARATOR(), structHash));
    }
}
